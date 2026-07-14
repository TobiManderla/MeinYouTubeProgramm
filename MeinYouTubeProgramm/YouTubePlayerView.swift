import SwiftUI
import WebKit
import Combine

// MARK: - Eingebettetes HTML (kein Bundle-Resource noetig)

private let kYTPlayerHTML = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;background:#000;overflow:hidden}
#player{width:100%;height:100%}
</style>
</head>
<body>
<div id="player"></div>
<script>
var tag=document.createElement('script');
tag.src='https://www.youtube.com/iframe_api';
document.head.appendChild(tag);
var player;
var _cc=false;
function applyCaptions(){
  try{if(_cc){player.setOption('captions','track',{})}else{player.unloadModule('captions')}}catch(e){}
}
function onYouTubeIframeAPIReady(){
  player=new YT.Player('player',{
    width:'100%',height:'100%',
    playerVars:{controls:0,disablekb:1,fs:0,iv_load_policy:3,playsinline:1,enablejsapi:1,origin:'http://localhost',cc_load_policy:0,cc_lang_pref:''},
    events:{
      onReady:function(){webkit.messageHandlers.ytPlayer.postMessage({event:'ready'})},
      onStateChange:function(e){
        if(e.data===1){applyCaptions()}
        webkit.messageHandlers.ytPlayer.postMessage({event:'stateChange',data:e.data})
      },
      onError:function(e){webkit.messageHandlers.ytPlayer.postMessage({event:'error',data:e.data})}
    }
  });
}
function loadVideo(id,start,cc){
  if(!player)return;
  _cc=cc;
  player.loadVideoById({videoId:id,startSeconds:start});
}
function getCurrentTime(){return(player&&player.getCurrentTime)?player.getCurrentTime():0}
function pauseVideo(){if(player)player.pauseVideo()}
function playVideo(){if(player)player.playVideo()}
</script>
</body>
</html>
"""

// MARK: - Coordinator

final class YouTubePlayerCoordinator: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView

    var onReady: (() -> Void)?
    var onStateChange: ((Int) -> Void)?
    var onError: ((Int) -> Void)?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isUserInteractionEnabled = false   // ClickShield: kein Tippen auf YT-Oberflaeche
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        // Safari-User-Agent damit YouTube-Embed nicht blockiert wird
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = wv

        super.init()

        // Wichtig: nach super.init() ueber webView.configuration (die Kopie des WKWebView)
        wv.configuration.userContentController.add(self, name: "ytPlayer")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytPlayer")
    }

    func loadHTML() {
        webView.loadHTMLString(kYTPlayerHTML, baseURL: URL(string: "http://localhost/"))
    }

    func loadVideo(videoId: String, startSec: Double, ccEnabled: Bool) {
        let js = "loadVideo('\(videoId)',\(startSec),\(ccEnabled ? "true" : "false"));"
        webView.evaluateJavaScript(js)
    }

    func pause()  { webView.evaluateJavaScript("pauseVideo();") }
    func resume() { webView.evaluateJavaScript("playVideo();") }

    func getCurrentTime(_ completion: @escaping (Double) -> Void) {
        webView.evaluateJavaScript("getCurrentTime();") { v, _ in
            completion(v as? Double ?? 0)
        }
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let d = msg.body as? [String: Any], let event = d["event"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            switch event {
            case "ready":       self?.onReady?()
            case "stateChange": self?.onStateChange?(d["data"] as? Int ?? -1)
            case "error":       self?.onError?(d["data"] as? Int ?? -1)
            default: break
            }
        }
    }
}

// MARK: - UIViewRepresentable

struct YouTubePlayerRepresentable: UIViewRepresentable {
    let coordinator: YouTubePlayerCoordinator
    func makeUIView(context: Context) -> WKWebView { coordinator.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
