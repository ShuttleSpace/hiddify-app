
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import HiddifyVpnPlugin from '../vpn/HiddifyVpnPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // OHOS VPN 控制通道：启动 `<bundle>:vpn` 扩展并把 vNIC fd 交给 Dart。
    flutterEngine.getPlugins()?.add(new HiddifyVpnPlugin());
  }
}
