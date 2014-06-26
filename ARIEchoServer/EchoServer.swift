//
//  EchoServer.swift
//  ARISockets
//
//  Created by Helge Hess on 6/13/14.
//
//

import ARISockets

class EchoServer {

  let port         : Int
  var listenSocket : PassiveSocket?
  var openSockets  = Dictionary<CInt, ActiveSocket>(minimumCapacity: 8)
  var appLog       : ((String) -> Void)?
  
  init(port: Int) {
    self.port = port
  }
  
  func log(s: String) {
    if let lcb = appLog {
      lcb(s)
    }
    else {
      println(s)
    }
  }
  
  func start() {
    listenSocket = PassiveSocket(address: sockaddr_in(port: port))
    if !listenSocket || !listenSocket! { // neat, eh? ;-)
      log("ERROR: could not create socket ...")
      return
    }
    
    log("Listen socket \(listenSocket)")
    
    let queue = dispatch_get_global_queue(0, 0)
    
    // Note: capturing self here
    listenSocket!.listen(queue, backlog: 5) {
      newSock in
      
      self.log("got new socket: \(newSock) nio=\(newSock.isNonBlocking)")
      newSock.isNonBlocking = true
      
      dispatch_async(dispatch_get_global_queue(0, 0)) {
        // Note: we need to keep the socket around!!
        self.openSockets[newSock.fd!] = newSock
      }
      
      self.sendWelcome(newSock)
      
      newSock.onRead  { self.handleIncomingData($0, expectedCount: $1) }
      newSock.onClose { ( fd: CInt ) -> Void in
        // we need to consume the return value to give peace to the closure
        dispatch_async(dispatch_get_global_queue(0, 0)) { () -> Void in
          _ = self.openSockets.removeValueForKey(fd)
        }
      }
      
      
    }
    
    log("Started running listen socket \(listenSocket)")
  }
  
  func stop() {
    listenSocket?.close()
    listenSocket = nil
  }
  
  func sendWelcome(sock: ActiveSocket) {
    // Hm, how to use println(), this doesn't work for me:
    //   println(s, target: sock)
    // (just writes the socket as a value, likely a tuple)
    
    // Doing individual writes is expensive, but swiftc segfaults if I just
    // add them up.
    sock.write("\r\n")
    sock.write("  /----------------------------------------------------\\\r\n")
    sock.write("  |     Welcome to the Always Right Institute!         |\r\n")
    sock.write("  |    I am an echo server with a zlight twist.        |\r\n")
    sock.write("  | Just type something and I'll shout it back at you. |\r\n")
    sock.write("  \\----------------------------------------------------/\r\n")
    sock.write("\r\nTalk to me Dave!\r\n")
    sock.write("> ")
  }
  
  func handleIncomingData(socket: ActiveSocket, expectedCount: Int) {
    // remove from openSockets if all has been read
    let (count, block) = socket.read()
    
    if count < 1 {
      log("EOF \(socket)")
      socket.close()
      return
    }
    
    logReceivedBlock(block, length: count)
    
    // maps the whole block. asyncWrite does not accept slices, can we add this?
    // (should adopt sth like IndexedCollection<T>?)
    let mblock = block.map({ $0 == 83 ? 90 : ($0 == 115 ? 122 : $0) })
    
    socket.asyncWrite(mblock, length: count)
    socket.write("> ")
  }

  func logReceivedBlock(block: CChar[], length: Int) {
    var s: String = ""
    block.withUnsafePointerToElements {
      p in
      s = String.fromCString(p)
    }
    if s.hasSuffix("\r\n") {
      s = s.substringToIndex(countElements(s) - 2)
    }
    
    log("read string: \(s)")
  }
  
}
