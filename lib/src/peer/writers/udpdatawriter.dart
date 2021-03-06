part of rtc_client;

class UDPDataWriter extends BinaryDataWriter {
  static final _logger = new Logger("dart_rtc_client.UDPDataWriter");
  static const int MAX_SEND_TRESHOLD = 200;
  static const int START_SEND_TRESHOLD = 30;
  static const int TRESHOLD_INCREMENT = 5;
  static const int ELAPSED_TIME_AFTER_SEND = 200;

  Timer _observerTimer;
  SendQueue _queue;
  int _c_packetsToSend;
  int _c_leftToRead;
  int _c_read;
  int _currentSequence;
  int resendCount = 0;
  int currentTreshold = 0;
  int _lastSendTime;

  UDPDataWriter(PeerConnection peer) : super(BINARY_PROTOCOL_UDP, peer) {
    _queue = new SendQueue();
  }

  Future<int> send(ByteBuffer buffer, int packetType, bool reliable) {
    _logger.finest("Sending buffer");
    _clearSequenceNumber();
    currentTreshold = START_SEND_TRESHOLD;
    Completer completer = new Completer();
    if (!reliable)
      completer.complete(0);
    int totalSequences = (buffer.lengthInBytes ~/ _writeChunkSize) + 1;

    int read = 0;
    int leftToRead = buffer.lengthInBytes;
    int signature = new Random().nextInt(100000000);
    _send(buffer, signature, totalSequences, buffer.lengthInBytes, packetType).then((int i) {
      if (!completer.isCompleted)
        completer.complete(1);
    });
    return completer.future;
  }

  Future<int> sendFile(Blob file) {
    _logger.finest("Sending file");
    _clearSequenceNumber();
    currentTreshold = START_SEND_TRESHOLD;
    Completer completer = new Completer();
    FileReader reader = new FileReader();
    int totalSequences = _getSequenceTotal(file.size);

    int read = 0;
    int leftToRead = file.size;
    int signature = new Random().nextInt(100000000);
    int toRead = file.size > BinaryDataWriter.MAX_FILE_BUFFER_SIZE ? BinaryDataWriter.MAX_FILE_BUFFER_SIZE : file.size;
    reader.readAsArrayBuffer(file.slice(read, read + toRead));
    reader.onLoadEnd.listen((ProgressEvent e) {
      _send(reader.result, signature, totalSequences, file.size, BINARY_TYPE_FILE).then((int i) {
        read += toRead;
        leftToRead -= toRead;
        if (read < file.size) {
          toRead = leftToRead > BinaryDataWriter.MAX_FILE_BUFFER_SIZE ? BinaryDataWriter.MAX_FILE_BUFFER_SIZE : file.size;
          reader.readAsArrayBuffer(file.slice(read, read + toRead));
        } else {
          completer.complete(1);
        }
      });

    });
    return completer.future;
  }

  Future<int> _send(ByteBuffer buffer, int signature, int totalSequences, int totalLength, int packetType) {
    _logger.finest("_send buffer");
    Completer<int> completer = new Completer<int>();
    int read = 0;
    int leftToRead = buffer.lengthInBytes;
    StreamSubscription sub;
    sub = _queue.onEmpty.listen((bool b) {
      _adjustTreshold();

      resendCount = 0;
      if (_observerTimer != null)
        _observerTimer.cancel();

      if (leftToRead == 0) {
        sub.cancel();
        completer.complete(1);
        _logger.finest("_sent all");
        return;
      }

      int t = (leftToRead /writeChunkSize).ceil();
      int treshold = t < currentTreshold ? t : currentTreshold;

      int added = 0;
      _queue.prepare(treshold);
      while (added < treshold) {
        int toRead = leftToRead > _writeChunkSize ? _writeChunkSize : leftToRead;
        ByteBuffer toAdd = _sublist(buffer, read, toRead);
        ByteBuffer b = addUdpHeader(
            toAdd,
            packetType,
            _currentSequence,
            totalSequences,
            signature,
            totalLength
        );

        read += toRead;
        leftToRead -= toRead;
        var si = new SendItem(b, _currentSequence, signature);
        si.totalSequences = totalSequences;
        si.signature = signature;

        _queue.add(si);
        _currentSequence++;
        added++;
        si.markSent();
        _signalWriteChunk(si.signature, si.sequence, si.totalSequences, si.buffer.lengthInBytes - SIZEOF_UDP_HEADER);
        write(si.buffer);
      }

      observe();
    });
    _queue.initialize();
    return completer.future;
  }





  void _clearSequenceNumber() {
    _currentSequence = 1;
  }

  void observe() {
    _observerTimer = new Timer.periodic(const Duration(milliseconds: 5), (Timer t) {
      if (_queue.itemCount > 0) {
        int now = new DateTime.now().millisecondsSinceEpoch;
        //SendItem item = _queue.first();
        for (int i = 0; i < _queue.items.length; i++) {
          SendItem item = _queue.items[i];
          if (item == null)
            continue;
          if ((item.sendTime + ELAPSED_TIME_AFTER_SEND) < now) {
            item.sendTime = now;
            write(item.buffer);
            resendCount++;
          }
        }

      }
    });
  }

  void _adjustTreshold() {
    if (resendCount > 0) {
      currentTreshold -= resendCount > 1 ? resendCount : TRESHOLD_INCREMENT;
      if (currentTreshold <= START_SEND_TRESHOLD)
        currentTreshold = START_SEND_TRESHOLD;
    } else {
      currentTreshold = currentTreshold >= MAX_SEND_TRESHOLD ? MAX_SEND_TRESHOLD : currentTreshold + TRESHOLD_INCREMENT;
    }
    if (resendCount > 0)
      _logger.finest("Resend count = $resendCount treshold = $currentTreshold");
  }

  void sendAck(ByteBuffer buffer) {
    window.setImmediate(() {
      write(buffer);
    });
  }

  void receiveAck(int signature, int sequence) {
    window.setImmediate(() {
      var si = _queue.removeItem(signature, sequence);
      if (si != null) {
        _signalWroteChunk(si.signature, si.sequence, si.totalSequences, si.buffer.lengthInBytes - SIZEOF_UDP_HEADER);
      }
    });
  }

  void _signalWriteChunk(int signature, int sequence, int totalSequences, int bytes) {
    window.setImmediate(() {
      listeners.where((l) => l is BinaryDataSentEventListener).forEach((BinaryDataSentEventListener l) {
        l.onWriteChunk(_peer, signature, sequence, totalSequences, bytes);
      });
    });
  }

  void _signalWroteChunk(int signature, int sequence, int totalSequences, int bytes) {
    window.setImmediate(() {
      listeners.where((l) => l is BinaryDataSentEventListener).forEach((BinaryDataSentEventListener l) {
        l.onWroteChunk(_peer, signature, sequence, totalSequences, bytes);
      });
    });
  }
}

class SendQueue {
  StreamController<bool> _queueEmptyController;
  Stream<bool> onEmpty;
  List<SendItem> _items;
  int _index;
  List<SendItem> get items => _items;
  int get itemCount => _length;
  int _length;
  SendQueue() {
    _queueEmptyController = new StreamController.broadcast(sync: true);
    //_queueEmptyController = new StreamController.broadcast<bool>();
    onEmpty = _queueEmptyController.stream;
  }

  void prepare(int count) {
    _index = 0;
    _length = 0;
    _items = new List<SendItem>(count);
  }

  void write() {

  }

  void add(SendItem item) {
    _items[_index++] = item;
    _length++;
  }

  SendItem removeItem(int signature, int sequence) {
    SendItem item = null;
    //_items.removeWhere((SendItem i) => i.signature == signature && i.sequence == sequence);
    for (int i = 0; i < items.length ; i++) {
      SendItem si = items[i];
      if (si != null) {
        if (si.signature == signature && si.sequence == sequence) {
          item = si;

          _items[i] = null;
          _length--;
          break;
        }
      }
    }

    if (_length == 0) {

      if (_queueEmptyController.hasListener)
        _queueEmptyController.add(true);
    }
    return item;
  }

  SendItem first() {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i] != null)
        return _items[i];
    }
    return null;
  }

  /*int _length() {
    int count = 0;
    for (int i = 0; i < _items.length; i++) {
      if (_items[i] != null)
      count++;
    }
    return count;
  }
  */
  void initialize() {
    if (_queueEmptyController.hasListener)
      _queueEmptyController.add(true);
  }
}

class SendItem {
  ByteBuffer buffer;
  int signature;
  int sequence;
  int totalSequences;
  int sendTime;
  bool sent = false;
  SendItem(this.buffer, this.sequence, this.signature);

  void markSent() {
    sent = true;
    sendTime = new DateTime.now().millisecondsSinceEpoch;
  }
}

