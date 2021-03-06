part of rtc_client;

const int SIZEOF8 = 1;
const int SIZEOF16 = 2;
const int SIZEOF32 = 4;
const int SIZEOF_UDP_HEADER = 20;
const int SIZEOF_TCP_HEADER = 12;

const int NULL_BYTE = 0x00;
const int FULL_BYTE = 0xFF;

const int BINARY_TYPE_COMMAND = 0;
const int BINARY_TYPE_STRING = 1;
const int BINARY_TYPE_FILE = 2;
const int BINARY_TYPE_CUSTOM = 3;
const int BINARY_TYPE_TEST = 10;

const int BINARY_PROTOCOL_UDP = 1;
const int BINARY_PROTOCOL_TCP = 2;

const int BINARY_PACKET_ACK = 0x01;
const int BINARY_PACKET_RESEND = 0x02;
const int BINARY_PACKET_REQUEST_RESEND = 0x03;

const int PROTOCOL_STARTBYTE_POSITION = 0;
const int PROTOCOL_PACKETTYPE_POSITION = 1;

const int UDP_PROTOCOL_SEQUENCE_POSITION = 2;
const int UDP_PROTOCOL_TOTALSEQUENCE_POSITION = 6;
const int UDP_PROTOCOL_BYTELENGTH_POSITION = 10;
const int UDP_PROTOCOL_TOTALBYTELENGTH_POSITION = 12;
const int UDP_PROTOCOL_SIGNATURE_POSITION = 16;
const int UDP_PROTOCOL_FIRST_CONTENT_POSITION = 20;

const int TCP_PROTOCOL_BYTELENGTH_POSITION = 2;
const int TCP_PROTOCOL_TOTALBYTELENGTH_POSITION = 4;
const int TCP_PROTOCOL_SIGNATURE_POSITION = 8;
const int TCP_PROTOCOL_FIRST_CONTENT_POSITION = 12;

/**
 * Binary reader/writer for Datachannel
 */
class BinaryData {
  static String lastError = "";
  static List<String> lookUp = gen();

  static ByteBuffer bufferFromString(String s) {
    Uint8List array = new Uint8List(s.length);
    for (int i = 0; i < s.length; i++) {
      array[i] = s.codeUnitAt(i);
    }

    return array.buffer;
  }

  static ByteBuffer bufferFromPacket(Packet p) {
    String packet = PacketFactory.get(p);
    return bufferFromString(packet);
  }

  static String stringFromList(List<int> l) {
    return new String.fromCharCodes(l);
  }

  static String stringFromBuffer2(ByteBuffer buffer) {
    return new String.fromCharCodes(new Uint8List.view(buffer));
  }

  static String stringFromBuffer1(ByteBuffer buffer) {
    StringBuffer sb = new StringBuffer();
    var list = new Uint8List.view(buffer);
    for (int i = 0; i < list.lengthInBytes; i++) {
      sb.writeCharCode(list[i]);
    }
    return sb.toString();
  }

  static String stringFromBuffer(ByteBuffer buffer) {
    StringBuffer sb = new StringBuffer();
    var list = new Uint8List.view(buffer);
    for (int i = 0; i < list.lengthInBytes; i++) {
      sb.write(lookUp[list[i]]);
    }
    return sb.toString();
  }

  static List<String> gen() {
    List<String> c = new List<String>(256);
    for (int i = 0; i < 256; i++) {
      c[i] = new String.fromCharCode(i);
    }
    return c;
  }

  /**
   * Converts ArrayBuffer to Packet
   */
  static Packet packetFromBuffer(ByteBuffer buffer) {
    PacketFactory.getPacketFromString(stringFromBuffer(buffer));
  }

  static ByteBuffer createAck(int signature, List<int> sequences) {
    ByteBuffer ackBuffer = new Uint8List(SIZEOF_UDP_HEADER + (sequences.length * SIZEOF32)).buffer;
    ByteData viewAck = new ByteData.view(ackBuffer);
    int length = sequences.length * SIZEOF32;
    viewAck.setUint8(
        PROTOCOL_STARTBYTE_POSITION,
        FULL_BYTE
    );

    viewAck.setUint8(
        PROTOCOL_PACKETTYPE_POSITION,
        BINARY_TYPE_COMMAND
    );

    viewAck.setUint32(
        UDP_PROTOCOL_SEQUENCE_POSITION,
        1
    );

    viewAck.setUint32(
        UDP_PROTOCOL_TOTALSEQUENCE_POSITION,
        1
    );

    viewAck.setUint16(
        UDP_PROTOCOL_BYTELENGTH_POSITION,
        length
    );

    viewAck.setUint32(
        UDP_PROTOCOL_TOTALBYTELENGTH_POSITION,
        length
    );

    viewAck.setUint32(
        UDP_PROTOCOL_SIGNATURE_POSITION,
        signature
    );
    int i = 0;

    for (int sequence in sequences) {
      viewAck.setUint32(UDP_PROTOCOL_FIRST_CONTENT_POSITION + i, sequence);
      i += SIZEOF32;
    }

    //if (!isValid(ackBuffer,BINARY_PROTOCOL_UDP )) {
    //  new Logger().warning("Created nonvalid ack response");
    //}
    return ackBuffer;
  }

  /**
   * Needs a bit of tuning =)
   */
  static bool hasHeader(ByteBuffer buffer) {
    ByteData view = new ByteData.view(buffer, 0, 1);
    try {
      if (view.getUint8(PROTOCOL_STARTBYTE_POSITION) == 0xFF)
        return true;
    } catch (e) {}

    return false;

  }

  static bool isCommand(ByteBuffer buffer) {
    //if (!isValidUdp(buffer))
    //  return buffer.lengthInBytes == SIZEOF_TCP_HEADER + 1;
    //return buffer.lengthInBytes == SIZEOF_UDP_HEADER + 1;
    return getPacketType(buffer) == BINARY_TYPE_COMMAND;
  }

  static int getCommand(ByteBuffer buffer) {
    return new ByteData.view(buffer).getUint8(20);
  }

  static int getSignature(ByteBuffer buffer) {
    ByteData view;
    if (!isValidUdp(buffer)) {
      view = new ByteData.view(buffer, 0, SIZEOF_TCP_HEADER);
      return view.getUint32(TCP_PROTOCOL_SIGNATURE_POSITION);
    }
    view = new ByteData.view(buffer, 0, SIZEOF_UDP_HEADER);
    return view.getUint32(UDP_PROTOCOL_SIGNATURE_POSITION);
  }

  static int getSequenceNumber(ByteBuffer buffer) {
    if (!isValidUdp(buffer))
      return 0;
    ByteData view = new ByteData.view(buffer, 0, 16);
    return view.getUint32(UDP_PROTOCOL_SEQUENCE_POSITION);
  }

  static int getPacketType(ByteBuffer buffer) {
    ByteData view = new ByteData.view(buffer, 0, 2);
    return view.getUint8(PROTOCOL_PACKETTYPE_POSITION);
  }

  static ByteBuffer writeUdpHeader(ByteBuffer buf, int packetType, int sequenceNumber, int totalSequences, int signature, int total) {
    Uint8List content = new Uint8List.view(buf);
    ByteBuffer resultBuffer = new Uint8List(buf.lengthInBytes + SIZEOF_UDP_HEADER).buffer;
    ByteData writer = new ByteData.view(resultBuffer);

    writer.setUint8(PROTOCOL_STARTBYTE_POSITION, FULL_BYTE); // 0
    writer.setUint8(PROTOCOL_PACKETTYPE_POSITION, packetType); // 1
    writer.setUint32(UDP_PROTOCOL_SEQUENCE_POSITION, sequenceNumber); // 2
    writer.setUint32(UDP_PROTOCOL_TOTALSEQUENCE_POSITION, totalSequences); //6
    writer.setUint16(UDP_PROTOCOL_BYTELENGTH_POSITION, buf.lengthInBytes); //10
    writer.setUint32(UDP_PROTOCOL_TOTALBYTELENGTH_POSITION, total); //12
    writer.setUint32(UDP_PROTOCOL_SIGNATURE_POSITION, signature); //16

    for (int i = 0; i < content.length; i++) {
      writer.setUint8(i + UDP_PROTOCOL_FIRST_CONTENT_POSITION, content[i]);
    }

    return writer.buffer;
  }

  static ByteBuffer writeTcpHeader(ByteBuffer buf, int packetType, int signature, int total) {
    Uint8List content = new Uint8List.view(buf);
    ByteBuffer resultBuffer = new Uint8List(buf.lengthInBytes + SIZEOF_TCP_HEADER).buffer;
    ByteData writer = new ByteData.view(resultBuffer);

    writer.setUint8(PROTOCOL_STARTBYTE_POSITION, FULL_BYTE); // 0
    writer.setUint8(PROTOCOL_PACKETTYPE_POSITION, packetType); // 1
    writer.setUint16(TCP_PROTOCOL_BYTELENGTH_POSITION, buf.lengthInBytes); // 2
    writer.setUint32(TCP_PROTOCOL_TOTALBYTELENGTH_POSITION, total);
    writer.setUint32(TCP_PROTOCOL_SIGNATURE_POSITION, signature);

    for (int i = 0; i < content.length; i++) {
      writer.setUint8(i + TCP_PROTOCOL_FIRST_CONTENT_POSITION, content[i]);
    }

    return writer.buffer;
  }

  static bool isValid(ByteBuffer buffer, int protocol) {
    if (protocol == BINARY_PROTOCOL_UDP){
      return isValidUdp(buffer);
    } else {
      return isValidTcp(buffer);
    }
  }

  static bool isValidTcp(ByteBuffer buf) {
    if (buf.lengthInBytes < SIZEOF_TCP_HEADER)
      return false;
    ByteData view = new ByteData.view(buf, 0, SIZEOF_TCP_HEADER);

    if (view.getUint8(PROTOCOL_STARTBYTE_POSITION) != FULL_BYTE) { // 0
      return false;
    }

    int packetType = view.getUint8(PROTOCOL_PACKETTYPE_POSITION); // 1
    if (packetType == null) {
      return false;
    }

    int byteLength = view.getUint16(TCP_PROTOCOL_BYTELENGTH_POSITION); // 2
    if (byteLength == null || byteLength <= 0) {
      return false;
    }

    int totalBytes = view.getUint32(TCP_PROTOCOL_TOTALBYTELENGTH_POSITION); // 4
    if (totalBytes == null || totalBytes < byteLength) {
      return false;
    }

    int signature = view.getUint32(TCP_PROTOCOL_SIGNATURE_POSITION); // 8
    if (signature == null) {
      return false;
    }

    return true;
  }

  static bool isValidUdp(ByteBuffer buf) {
    if (buf.lengthInBytes < SIZEOF_UDP_HEADER)
      return false;

    ByteData view = new ByteData.view(buf, 0, SIZEOF_UDP_HEADER);

    if (view.getUint8(PROTOCOL_STARTBYTE_POSITION) != FULL_BYTE) { // 0
      return false;
    }

    int packetType = view.getUint8(PROTOCOL_PACKETTYPE_POSITION); // 1
    if (packetType == null) {
      lastError = "Packet type: $packetType";
      return false;
    }

    int sequenceNumber = view.getUint32(UDP_PROTOCOL_SEQUENCE_POSITION); // 2
    if (sequenceNumber == null || sequenceNumber < 1) {
      lastError = "Sequence number: $sequenceNumber";
      return false;
    }

    int totalSequences = view.getUint32(UDP_PROTOCOL_TOTALSEQUENCE_POSITION); // 6
    if (totalSequences == null || totalSequences < sequenceNumber) {
      lastError = "Total sequences: $totalSequences";
      return false;
    }

    int byteLength = view.getUint16(UDP_PROTOCOL_BYTELENGTH_POSITION); // 10
    if (byteLength == null || byteLength <= 0) {
      lastError = "Bytelength: $byteLength";
      return false;
    }

    int totalBytes = view.getUint32(UDP_PROTOCOL_TOTALBYTELENGTH_POSITION); // 12
    if (totalBytes == null || totalBytes < byteLength) {
      lastError = "Total bytes: $totalBytes";
      return false;
    }

    int signature = view.getUint32(UDP_PROTOCOL_SIGNATURE_POSITION); // 16
    if (signature == null) {
      lastError = "Signature: $signature";
      return false;
    }

    return true;
  }
}

