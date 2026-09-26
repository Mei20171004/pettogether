const trustedProHostingOrigin = 'https://pettogether-pro.web.app';

/// The Custom Token may be injected only into our dedicated Hosting origin.
bool isTrustedWebAuthPage(Uri openedUrl, Uri? currentUrl) =>
    openedUrl.scheme == 'https' &&
    openedUrl.origin == trustedProHostingOrigin &&
    currentUrl?.scheme == 'https' &&
    currentUrl?.origin == trustedProHostingOrigin;
