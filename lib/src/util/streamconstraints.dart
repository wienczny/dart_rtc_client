part of rtc_client;

/**
 * Constraints for Peer stream
 */
class StreamConstraints implements Constraints {
  /* bitrate of the stream */
  int _bitRate;

  /** Sets the bitrate of the stream */
  set bitRate(int value) => setBitrate(value);

  /**
   * Constructor
   */
  StreamConstraints() {
    _bitRate = 200;
  }

  /**
   * Sets the bitrate of the stream
   */
  StreamConstraints setBitrate(int value) {
    _bitRate = value;
    return this;
  }

  /**
   * Implements Constraints toMap
   */
  Map toMap() {
    return {
      'mandatory' : {},
      'optional' : [{'bandwidth': _bitRate}]
    };
  }
}