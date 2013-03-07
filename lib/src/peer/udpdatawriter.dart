part of rtc_client;

class UDPDataWriter extends BinaryDataWriter {

  Map<int, List<StoreEntry>> _sentPackets;
  Map<int, Completer> _completers;
  
  Timer _sendTimer;
  int _currentSequence = 0;
  bool _canSend = true;
  int _lastSent = 0;

  UDPDataWriter() : super(BINARY_PROTOCOL_UDP) {
    _sentPackets = new Map<int, List<StoreEntry>>();
    _completers = new Map<int, Completer>();
    _sendTimer = new Timer.repeating(const Duration(milliseconds: 1), _timerTick);
  }

  Future<bool> send(ArrayBuffer buffer, int packetType) {
    Completer completer = new Completer();
    
    int totalSequences = (buffer.byteLength ~/ _writeChunkSize) + 1;
    int sequence = 1;
    int read = 0;
    int signature = new DateTime.now().millisecondsSinceEpoch  ~/1000;
    _completers[signature] = completer;
    while (read < buffer.byteLength) {
      int toRead = buffer.byteLength > _writeChunkSize ? _writeChunkSize : buffer.byteLength;
      ArrayBuffer b = addUdpHeader(
          buffer.slice(read, read + toRead),
          packetType,
          sequence,
          totalSequences,
          signature,
          buffer.byteLength
      );
      _storeBuffer(b, signature, sequence);
      sequence++;
      read += toRead;
    }
    return completer.future;
  }

  void _timerTick(Timer t) {
    int now = new DateTime.now().millisecondsSinceEpoch;
    
    _sentPackets.forEach((int key, List<StoreEntry> entries) {

      if (_writeChannel.bufferedAmount == 0 && entries.length > 0) {
        StoreEntry entry = entries[0];
        if (!entry.sent) {
          _send(entry.buffer, true);
          new Logger().Debug("Sent chunk ${entry.sequence}");
          entry.markSent();
          if (!entry.resend) {
            new Logger().Debug("Remove STOREENTRY");
            removeStoreEntryFromBuffer(key, entry);
          }
        } else {
          if ((entry.timeReSent + currentLatency) < now) {
            if (_currentSequence == entry.sequence)
              _roundTripCalculator.addToLatency(50);

            _send(entry.buffer, true);
            new Logger().Debug("RE-Sent chunk ${entry.sequence} RESEND = ${entry.resend} PACKETTYPE = ${BinaryData.getPacketType(entry.buffer)}");
            entry.markReSent();
            _currentSequence = entry.sequence;
          }
        }
        
        
      }
    });

  }

  ArrayBuffer findSentData(int signature, int sequence) {
    if (!_sentPackets.containsKey(signature));
      return null;

    List<StoreEntry> buffers = _sentPackets[signature];
    for (int i = 0; i < buffers.length; i++) {
      StoreEntry se = buffers[i];

      if (se.sequence == sequence)
        return se.buffer;
    }

    return null;
  }

  void writeAck(int signature, int sequence) {
    new Logger().Debug("WRITING ACK");
    _storeBuffer(BinaryData.createAck(signature, sequence), signature, sequence, false);
  }

  void receiveAck(int signature, int sequence) {
    StoreEntry se = findStoredBuffer(signature, sequence);
    if (se != null) {
      calculateLatency(se.timeSent);
      new Logger().Debug("Adjusting latency, currently $currentLatency");
      removeStoreEntryFromBuffer(signature, se);
      
    }
  }

  void removeStoreEntryFromBuffer(int signature, StoreEntry se) {
    if (!_sentPackets.containsKey(signature)) {
      new Logger().Warning("Attempted to remove store entry with signature $signature, Buffer not found.");
      return;
    }

    int index = _sentPackets[signature].indexOf(se);
    if (index < 0) {
      new Logger().Warning("Attempted to remove store entry with signature $signature, Not found.");
      return;
    }

    // Try if this helps for concurrent modification errors
    // Should push the execution of this block to the end of event loops?
    window.setImmediate(() {
      _sentPackets[signature].removeAt(index);
      if (_sentPackets[signature].length == 0) {
        _sentPackets.remove(signature);
        if (_completers.containsKey(signature)) {
          _completers[signature].complete(true);
          _completers.remove(signature);
        }
      }
    });
  }

  void _storeBuffer(ArrayBuffer buf, int signature, int sequence, [bool resend]) {
    var se = new StoreEntry(sequence, buf);
    if (?resend)
      se.resend = resend;
    _store(signature, se);
  }

  void _store(int signature, StoreEntry se) {
    if (!_sentPackets.containsKey(signature))
      _sentPackets[signature] = new List<StoreEntry>();

    _sentPackets[signature].add(se);
  }

  StoreEntry findStoredBuffer(int time, int sequence) {
    if (!_sentPackets.containsKey(time))
      return null;

    for (int i = 0; i < _sentPackets[time].length; i++) {
      StoreEntry se = _sentPackets[time][i];
      if (se.sequence == sequence)
        return se;
    }
    return null;
  }

}

class StoreEntry implements Comparable{
  int timeStored;
  int timeSent;
  int timeReSent;
  int sequence;
  bool resend = true;
  bool sent = false;
  ArrayBuffer buffer;

  StoreEntry(this.sequence, this.buffer) {
    timeStored = new DateTime.now().millisecondsSinceEpoch;
  }

  void markSent() {
    sent = true;
    timeSent = new DateTime.now().millisecondsSinceEpoch;
    timeReSent = new DateTime.now().millisecondsSinceEpoch;
  }

  void markReSent() {
    timeReSent = new DateTime.now().millisecondsSinceEpoch;
  }

  int compareTo(StoreEntry e) {
    if (!sent && e.sent)
      return -1;

    if (sent && e.sent)
      return 0;

    if (!sent && !e.sent)
      return 0;

    if (sent && !e.sent)
      return 1;
  }
}
