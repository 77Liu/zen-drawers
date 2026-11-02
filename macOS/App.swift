import Cocoa
import WebKit
import UniformTypeIdentifiers

func argument(_ name:String) -> String? { guard let index=CommandLine.arguments.firstIndex(of:name),index+1<CommandLine.arguments.count else { return nil }; return CommandLine.arguments[index+1] }
let resourceRoot = Bundle.main.resourceURL!.appendingPathComponent("web")
let serveOnly=CommandLine.arguments.contains("--serve-only")
let dataRoot = serveOnly && argument("--data-dir") != nil ? URL(fileURLWithPath:argument("--data-dir")!) : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zen")
let port=UInt16(argument("--port") ?? "19763") ?? 19763

@MainActor
final class ZenApplication: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private var window:NSWindow!
    private var web:WKWebView!
    private var server:LocalServer!
    private var store:LocalStore!
    private var downloads=[WKDownload]()
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let other=NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "local.zen.drawers").first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}) { other.activate(options:.activateIgnoringOtherApps); NSApp.terminate(nil); return }
        do {
            store=try LocalStore(root:dataRoot)
            server=LocalServer(store:store,webRoot:resourceRoot,port:port)
            try server.start { [weak self] error in DispatchQueue.main.async { if let error=error { self?.failed(error) } else { self?.showWindow() } } }
        } catch { failed(error) }
    }
    private func showWindow() {
        let config=WKWebViewConfiguration();config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically=true
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1320,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Zen 抽屉";window.minSize=NSSize(width:780,height:580);window.contentView=web;window.center();
        // Window geometry lives in .zen as well; no persistent WebKit website store is used.
        window.setFrameAutosaveName("")
        if let data=try? Data(contentsOf:dataRoot.appendingPathComponent("window.json")),let info=try? JSONSerialization.jsonObject(with:data) as? [String:Double],let w=info["width"],let h=info["height"] { window.setContentSize(NSSize(width:max(780,w),height:max(580,h)));window.center() }
        web.load(URLRequest(url:URL(string:server.origin+"/")!));makeMenu();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    private func makeMenu() {
        let menu=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu();appMenu.addItem(withTitle:"关于 Zen 抽屉",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"");appMenu.addItem(.separator());appMenu.addItem(withTitle:"退出 Zen 抽屉",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");appItem.submenu=appMenu;menu.addItem(appItem)
        let fileItem=NSMenuItem(),fileMenu=NSMenu(title:"文件");for (title,action,key) in [("打开数据文件夹",#selector(openData),""),("在浏览器打开",#selector(openBrowser),""),("重新加载",#selector(reload),"r")] { let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=self;fileMenu.addItem(item) };fileItem.submenu=fileMenu;menu.addItem(fileItem)
        let editItem=NSMenuItem(),edit=NSMenu(title:"编辑");for (title,selector,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] { edit.addItem(withTitle:title,action:NSSelectorFromString(selector),keyEquivalent:key) };editItem.submenu=edit;menu.addItem(editItem)
        let windowItem=NSMenuItem(),windows=NSMenu(title:"窗口");windows.addItem(withTitle:"最小化",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m");windowItem.submenu=windows;menu.addItem(windowItem);NSApp.windowsMenu=windows;NSApp.mainMenu=menu
    }
    @objc private func openData(){NSWorkspace.shared.open(dataRoot)}
    @objc private func openBrowser(){NSWorkspace.shared.open(URL(string:server.origin+"/")!)}
    @objc private func reload(){web.reload()}
    private func failed(_ error:Error){let alert=NSAlert();alert.messageText="Zen 抽屉未能启动";alert.informativeText="\(error.localizedDescription)\n\n如果是地址占用，请退出旧版 Zen 或停止旧版本机服务，再重开。你的数据保留在 ~/.zen。";alert.runModal();NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {window?.makeKeyAndOrderFront(nil);return true}
    func applicationWillTerminate(_ notification:Notification){if let frame=window?.contentLayoutRect,let data=try? JSONSerialization.data(withJSONObject:["width":frame.width,"height":frame.height]){try? data.write(to:dataRoot.appendingPathComponent("window.json"),options:.atomic)};try? store?.backup()}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        if navigationAction.shouldPerformDownload {decisionHandler(.download);return}
        if let url=navigationAction.request.url,let host=url.host,host != "127.0.0.1",["http","https"].contains(url.scheme ?? "") {NSWorkspace.shared.open(url);decisionHandler(.cancel);return}
        decisionHandler(.allow)
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {if let url=navigationAction.request.url,["http","https"].contains(url.scheme ?? ""){NSWorkspace.shared.open(url)};return nil}
    func webView(_ webView:WKWebView,runOpenPanelWith parameters:WKOpenPanelParameters,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping([URL]?)->Void){let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowsMultipleSelection=parameters.allowsMultipleSelection;panel.beginSheetModal(for:window){result in completionHandler(result == .OK ? panel.urls:nil)}}
    func webView(_ webView:WKWebView,navigationAction:WKNavigationAction,didBecome download:WKDownload){download.delegate=self;downloads.append(download)}
    func webView(_ webView:WKWebView,navigationResponse:WKNavigationResponse,didBecome download:WKDownload){download.delegate=self;downloads.append(download)}
    func download(_ download:WKDownload,decideDestinationUsing response:URLResponse,suggestedFilename:String,completionHandler:@escaping(URL?)->Void){let panel=NSSavePanel();panel.nameFieldStringValue=suggestedFilename;panel.canCreateDirectories=true;panel.showsTagField=false;panel.isExtensionHidden=false;panel.directoryURL=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first;if let type=UTType(filenameExtension:(suggestedFilename as NSString).pathExtension){panel.allowedContentTypes=[type];panel.allowsOtherFileTypes=true};panel.beginSheetModal(for:window){result in completionHandler(result == .OK ? panel.url:nil)}}
    func downloadDidFinish(_ download:WKDownload){downloads.removeAll{$0 === download}}
    func download(_ download:WKDownload,didFailWithError error:Error,resumeData:Data?){downloads.removeAll{$0 === download}}
}

@main
struct ZenMain {
static func main() {
if serveOnly {
    do {let store=try LocalStore(root:dataRoot),server=LocalServer(store:store,webRoot:resourceRoot,port:port);try server.start{error in if let error=error {fputs("\(error)\n",stderr);exit(1)}else{print("READY \(server.origin) \(dataRoot.path)");fflush(stdout)}};withExtendedLifetime(server){dispatchMain()}}catch{fputs("\(error)\n",stderr);exit(1)}
} else {
    MainActor.assumeIsolated {let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=ZenApplication();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}

}
}
