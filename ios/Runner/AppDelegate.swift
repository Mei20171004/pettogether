import Flutter
import LinkPresentation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var invitationShareChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "pettogether/invitation_share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.shareInvitation(call, result: result)
    }
    invitationShareChannel = channel
  }

  private func shareInvitation(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let link = arguments["link"] as? String,
      let title = arguments["title"] as? String,
      let logoData = arguments["logo"] as? FlutterStandardTypedData,
      let logo = UIImage(data: logoData.data),
      let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow }),
      var presenter = window.rootViewController
    else {
      result(FlutterError(code: "share_unavailable", message: "Unable to present invitation share sheet", details: nil))
      return
    }

    while let presented = presenter.presentedViewController {
      presenter = presented
    }

    let item = InvitationShareItem(link: link, title: title, logo: logo)
    let sheet = UIActivityViewController(activityItems: [item], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 1,
        height: 1
      )
      popover.permittedArrowDirections = []
    }
    presenter.present(sheet, animated: true) {
      result(nil)
    }
  }
}

private final class InvitationShareItem: NSObject, UIActivityItemSource {
  let link: String
  let title: String
  let logo: UIImage

  init(link: String, title: String, logo: UIImage) {
    self.link = link
    self.title = title
    self.logo = logo
  }

  func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
    link
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    itemForActivityType activityType: UIActivity.ActivityType?
  ) -> Any? {
    link
  }

  func activityViewController(
    _ activityViewController: UIActivityViewController,
    subjectForActivityType activityType: UIActivity.ActivityType?
  ) -> String {
    title
  }

  func activityViewControllerLinkMetadata(
    _ activityViewController: UIActivityViewController
  ) -> LPLinkMetadata? {
    let metadata = LPLinkMetadata()
    metadata.title = title
    metadata.originalURL = URL(string: link)
    metadata.url = metadata.originalURL
    metadata.iconProvider = NSItemProvider(object: logo)
    metadata.imageProvider = NSItemProvider(object: logo)
    return metadata
  }
}
