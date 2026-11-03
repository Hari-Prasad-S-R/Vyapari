/// Web-safe subset of the server: the [Room] engine without sockets, files
/// or SQLite. The app uses it to run offline games against bots on every
/// platform, including the browser.
library;

export 'src/room.dart';
export 'src/support.dart';
