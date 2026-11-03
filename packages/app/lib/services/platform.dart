/// Platform services. On web these are stubs: browsers cannot host a server
/// or listen for UDP, so web is join-only (online server).
library;

export 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';
