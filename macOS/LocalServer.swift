import Foundation
import Network

final class LocalServer {
    private let queue = DispatchQueue(label:"local.zen.http", qos:.userInitiated, attributes:.concurrent)
    private var listener: NWListener?
    let store: LocalStore
    let webRoot: URL
    let port: UInt16
    var origin: String { "http://127.0.0.1:\(port)" }
    init(store: LocalStore, webRoot: URL, port: UInt16) { self.store=store; self.webRoot=webRoot; self.port=port }
    func start(completion: @escaping (Error?) -> Void) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
        let listener = try NWListener(using:params)
        self.listener=listener
        var announced=false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: if !announced { announced=true; completion(nil) }
            case .failed(let error): if !announced { announced=true; completion(error) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue:queue)
    }
    private func accept(_ connection:NWConnection) {
        connection.start(queue:queue)
        receive(connection, buffer:Data())
    }
    private func receive(_ connection:NWConnection, buffer:Data) {
        connection.receive(minimumIncompleteLength:1, maximumLength:65536) { [weak self] bytes,_,complete,error in
            guard let self=self else { connection.cancel(); return }
            var data=buffer; if let bytes=bytes { data.append(bytes) }
            if data.count > 268435456 { self.reply(connection,413,Data()); return }
            if let range=data.range(of:Data("\r\n\r\n".utf8)), let header=String(data:data[..<range.lowerBound],encoding:.utf8) {
                let lines=header.components(separatedBy:"\r\n")
                let first=(lines.first ?? "").split(separator:" ")
                var headers=[String:String]()
                for line in lines.dropFirst() { if let i=line.firstIndex(of:":") { headers[String(line[..<i]).lowercased()]=line[line.index(after:i)...].trimmingCharacters(in:.whitespaces) } }
                let length=Int(headers["content-length"] ?? "0") ?? 0
                if length < 0 || length > 268435456 { self.reply(connection,413,Data()); return }
                if first.count >= 2 && data.count-range.upperBound >= length {
                    self.handle(connection,method:String(first[0]),target:String(first[1]),headers:headers,body:data.subdata(in:range.upperBound..<(range.upperBound+length))); return
                }
            }
            if complete || error != nil { connection.cancel() } else { self.receive(connection,buffer:data) }
        }
    }
    private func reply(_ connection:NWConnection,_ status:Int,_ body:Data,_ type:String="application/json; charset=utf-8") {
        let names=[200:"OK",400:"Bad Request",403:"Forbidden",404:"Not Found",409:"Conflict",413:"Payload Too Large",500:"Internal Server Error"]
        var result=Data("HTTP/1.1 \(status) \(names[status] ?? "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n".utf8)
        result.append(body)
        connection.send(content:result,completion:.contentProcessed { _ in connection.cancel() })
    }
    private func json(_ connection:NWConnection,_ object:Any,_ status:Int=200) { reply(connection,status,(try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys)) ?? Data("{}".utf8)) }
    private func handle(_ connection:NWConnection,method:String,target:String,headers:[String:String],body:Data) {
        guard headers["host"] == "127.0.0.1:\(port)" else { json(connection,[:],403); return }
        let raw=String(target.split(separator:"?",maxSplits:1,omittingEmptySubsequences:false)[0])
        guard let path=raw.removingPercentEncoding else { json(connection,[:],400); return }
        if path.hasPrefix("/api/") {
            if let source=headers["origin"],source != origin { json(connection,[:],403); return }
            if headers["sec-fetch-site"] == "cross-site" { json(connection,[:],403); return }
            if method != "GET" && headers["x-zen-token"] != store.token { json(connection,[:],403); return }
            do {
                if path == "/api/state" && method == "GET" { json(connection,store.snapshot()); return }
                if path.hasPrefix("/api/files/") {
                    let id=String(path.dropFirst("/api/files/".count))
                    if method == "GET" { let (data,mime)=try store.file(id); reply(connection,200,data,mime); return }
                    if method == "PUT" { try store.putFile(id,data:body,mime:headers["content-type"] ?? "application/octet-stream"); json(connection,["ok":true]); return }
                }
                let object=(try? JSONSerialization.jsonObject(with:body)) as? [String:Any] ?? [:]
                if path == "/api/import-image", method == "POST", let source=object["url"] as? String, let url=URL(string:source), ["http","https"].contains(url.scheme?.lowercased() ?? "") {
                    var request=URLRequest(url:url); request.timeoutInterval=30
                    URLSession.shared.dataTask(with:request) { data,response,error in
                        guard error == nil, let response=response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let data=data, data.count <= 26214400, let mime=response.mimeType, ["image/png","image/jpeg","image/gif","image/webp","image/avif"].contains(mime) else { self.json(connection,["error":"图片下载失败或不支持（最大 25 MB）"],400); return }
                        self.reply(connection,200,data,mime)
                    }.resume(); return
                }
                if path == "/api/item",method == "POST",let key=object["key"] as? String { json(connection,try store.set(key:key,value:object["value"] as? String)); return }
                if path == "/api/clear",method == "POST" { json(connection,try store.clear()); return }
                if path == "/api/bootstrap",method == "POST",let incoming=object["storage"] as? [String:String] { json(connection,try store.bootstrap(incoming)); return }
                if path == "/api/migration-complete",method == "POST" { try store.completeMigration(); json(connection,["ok":true]); return }
                json(connection,[:],404)
            } catch { json(connection,["error":error.localizedDescription],500) }
            return
        }
        if path == "/health" { json(connection,["app":"zen-drawers", "runtime":"native", "ok":true]); return }
        guard method == "GET" else { json(connection,[:],404); return }
        let relative=path == "/" ? "Zen抽屉.html" : String(path.dropFirst())
        guard relative == "Zen抽屉.html" || relative == "manifest.webmanifest" || relative == "zen-sw.js" || relative.hasPrefix("assets/") else { json(connection,[:],404); return }
        let url=webRoot.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(webRoot.standardizedFileURL.path+"/"),let data=try? Data(contentsOf:url) else { json(connection,[:],404); return }
        let types=["html":"text/html; charset=utf-8", "js":"text/javascript; charset=utf-8", "css":"text/css; charset=utf-8", "json":"application/json", "webmanifest":"application/manifest+json", "png":"image/png", "svg":"image/svg+xml", "txt":"text/plain; charset=utf-8"]
        reply(connection,200,data,types[url.pathExtension] ?? "application/octet-stream")
    }
}
