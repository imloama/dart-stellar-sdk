import 'package:fixnum/fixnum.dart' as fixNum;
import 'package:tweetnacl/tweetnacl.dart' as ed25519;
import 'dart:typed_data';
import "base32.dart";
import 'transaction.dart';
import 'util.dart';
import 'xdr/xdr_data.dart';
import 'xdr/xdr_enum.dart';
import 'xdr/xdr_type.dart';
import 'xdr/xdr_other.dart';

class VersionByte {
  final _value;
  const VersionByte._internal(this._value);
  toString() => 'VersionByte.$_value';
  VersionByte(this._value);
  getValue() => this._value;

  static const ACCOUNT_ID = const VersionByte._internal((6 << 3)); // G
  static const SEED = const VersionByte._internal((18 << 3)); // S
  static const PRE_AUTH_TX = const VersionByte._internal((19 << 3)); // T
  static const SHA256_HASH = const VersionByte._internal((23 << 3)); // X

}

class StrKey {
  static String encodeStellarAccountId(Uint8List data) {
    return encodeCheck(VersionByte.ACCOUNT_ID, data);
  }

  static Uint8List decodeStellarAccountId(String data) {
    return decodeCheck(VersionByte.ACCOUNT_ID, data);
  }

  static String encodeStellarSecretSeed(Uint8List data) {
    return encodeCheck(VersionByte.SEED, data);
  }

  static Uint8List decodeStellarSecretSeed(String data) {
    return decodeCheck(VersionByte.SEED, data);
  }

  static String encodePreAuthTx(Uint8List data) {
    return encodeCheck(VersionByte.PRE_AUTH_TX, data);
  }

  static Uint8List decodePreAuthTx(String data) {
    return decodeCheck(VersionByte.PRE_AUTH_TX, data);
  }

  static String encodeSha256Hash(Uint8List data) {
    return encodeCheck(VersionByte.SHA256_HASH, data);
  }

  static Uint8List decodeSha256Hash(String data) {
    return decodeCheck(VersionByte.SHA256_HASH, data);
  }

  static String encodeCheck(VersionByte versionByte, Uint8List data) {
    List<int> output = List();
    output.add(versionByte.getValue());
    output.addAll(data);

    Uint8List payload = Uint8List.fromList(output);
    Uint8List checksum = StrKey.calculateChecksum(payload);
    output.addAll(checksum);
    Uint8List unencoded = Uint8List.fromList(output);

    String charsEncoded = base32.encode(unencoded);

    return charsEncoded;
  }

  static Uint8List decodeCheck(VersionByte versionByte, String encData) {
    Uint8List decoded = base32.decode(encData);
    int decodedVersionByte = decoded[0];
    Uint8List payload =
        Uint8List.fromList(decoded.getRange(0, decoded.length - 2).toList());
    Uint8List data =
        Uint8List.fromList(payload.getRange(1, payload.length).toList());
    Uint8List checksum = Uint8List.fromList(
        decoded.getRange(decoded.length - 2, decoded.length).toList());

    if (decodedVersionByte != versionByte.getValue()) {
      throw new FormatException("Version byte is invalid");
    }

    Uint8List expectedChecksum = StrKey.calculateChecksum(payload);

    if (!eq(expectedChecksum, checksum)) {
      throw new FormatException("Checksum invalid");
    }

    return data;
  }

  static Uint8List calculateChecksum(Uint8List bytes) {
// This code calculates CRC16-XModem checksum
// Ported from https://github.com/alexgorbatchev/node-crc
    fixNum.Int32 crc = fixNum.Int32(0x0000);
    int count = bytes.length;
    int i = 0;
    fixNum.Int32 code;

    while (count > 0) {
      code = crc.shiftRightUnsigned(8) & 0xFF;
      code ^= bytes[i++] & 0xFF;
      code ^= code.shiftRightUnsigned(4);
      crc = crc << 8 & 0xFFFF;
      crc ^= code;
      code = code << 5 & 0xFFFF;
      crc ^= code;
      code = code << 7 & 0xFFFF;
      crc ^= code;
      count--;
    }

// little-endian
    return Uint8List.fromList([crc.toInt(), crc.shiftRightUnsigned(8).toInt()]);
  }
}

/// Holds a Stellar keypair.
class KeyPair {
  Uint8List _mPublicKey = null;
  Uint8List _mPrivateKey = null;
  static Uint8List _mPrivateKey_seed = null;

  ///Creates a new KeyPair from the given public and private keys.
  KeyPair(Uint8List publicKey, Uint8List privateKey) {
    _mPublicKey = checkNotNull(publicKey, "publicKey cannot be null");
    _mPrivateKey = privateKey;
  }

  ///Returns true if this Keypair is capable of signing
  bool canSign() {
    return _mPrivateKey != null;
  }

  ///<strong>Insecure</strong> Creates a new Stellar KeyPair from a strkey encoded Stellar secret seed.
  ///This method is <u>insecure</u>. Use only if you are aware of security implications.
  static KeyPair fromSecretSeed(String seed) {
    Uint8List decoded = StrKey.decodeStellarSecretSeed(seed);
    KeyPair keypair = fromSecretSeedList(decoded);

    return keypair;
  }

  ///Creates a new Stellar keypair from a raw 32 byte secret seed.
  static KeyPair fromSecretSeedList(Uint8List seed) {
    _mPrivateKey_seed = seed;
    ed25519.KeyPair kp = ed25519.Signature.keyPair_fromSeed(seed);
    return new KeyPair(kp.publicKey, kp.secretKey);
  }

  ///Creates a new Stellar KeyPair from a strkey encoded Stellar account ID.
  static KeyPair fromAccountId(String accountId) {
    Uint8List decoded = StrKey.decodeStellarAccountId(accountId);
    return fromPublicKey(decoded);
  }

  ///Creates a new Stellar keypair from a 32 byte address.
  static KeyPair fromPublicKey(Uint8List publicKey) {
    return new KeyPair(publicKey, null);
  }

  ///Generates a random Stellar keypair.
  static KeyPair random() {
    Uint8List secret = ed25519.TweetNaclFast.randombytes(32);
    return fromSecretSeedList(secret);
  }

  ///Returns the human readable account ID encoded in strkey.
  String get accountId => StrKey.encodeStellarAccountId(_mPublicKey);

  ///Returns the human readable secret seed encoded in strkey.
  String get secretSeed => StrKey.encodeStellarSecretSeed(_mPrivateKey_seed);

  Uint8List get publicKey => _mPublicKey;

  XdrSignatureHint get signatureHint {
    XdrDataOutputStream xdrOutputStream = new XdrDataOutputStream();
    XdrPublicKey.encode(xdrOutputStream, this.xdrPublicKey);
    Uint8List publicKeyBytes = Uint8List.fromList(xdrOutputStream.bytes);
    Uint8List signatureHintBytes = Uint8List.fromList(publicKeyBytes
        .getRange(publicKeyBytes.length - 4, publicKeyBytes.length)
        .toList());

    XdrSignatureHint signatureHint = new XdrSignatureHint();
    signatureHint.signatureHint = signatureHintBytes;
    return signatureHint;
  }

  XdrPublicKey get xdrPublicKey {
    XdrPublicKey publicKey = new XdrPublicKey();
    publicKey.setDiscriminant(XdrPublicKeyType.PUBLIC_KEY_TYPE_ED25519);
    XdrUint256 uint256 = new XdrUint256();
    uint256.uint256 = this.publicKey;
    publicKey.setEd25519(uint256);
    return publicKey;
  }

  XdrSignerKey get xdrSignerKey {
    XdrSignerKey signerKey = new XdrSignerKey();
    signerKey.discriminant = XdrSignerKeyType.SIGNER_KEY_TYPE_ED25519;
    XdrUint256 uint256 = new XdrUint256();
    uint256.uint256 = this.publicKey;
    signerKey.ed25519 = uint256;
    return signerKey;
  }

  static KeyPair fromXdrPublicKey(XdrPublicKey key) {
    return KeyPair.fromPublicKey(key.getEd25519().uint256);
  }

  static KeyPair fromXdrSignerKey(XdrSignerKey key) {
    return KeyPair.fromPublicKey(key.ed25519.uint256);
  }

  ///Sign the provided data with the keypair's private key.
  Uint8List sign(Uint8List data) {
    if (_mPrivateKey == null) {
      throw new Exception(
          "KeyPair does not contain secret key. Use KeyPair.fromSecretSeed method to create a new KeyPair with a secret key.");
    }
    ed25519.Signature sgr = ed25519.Signature(null, _mPrivateKey);
    return sgr.detached(data);
  }

  ///Sign the provided data with the keypair's private key and returns {@link DecoratedSignature}.
  XdrDecoratedSignature signDecorated(Uint8List data) {
    Uint8List signatureBytes = this.sign(data);

    XdrSignature signature = XdrSignature();
    signature.signature = signatureBytes;

    XdrDecoratedSignature decoratedSignature = new XdrDecoratedSignature();
    decoratedSignature.hint = this.signatureHint;
    decoratedSignature.signature = signature;
    return decoratedSignature;
  }

  ///Verify the provided data and signature match this keypair's public key.
  bool verify(Uint8List data, Uint8List signature) {
    ed25519.Signature sgr = ed25519.Signature(_mPublicKey, null);
    return sgr.detached_verify(data, signature);
  }
}

///Signer is a helper class that creates XdrSignerKey objects.
class SignerKey {
  ///Create <code>ed25519PublicKey</code> XdrSignerKey from KeyPair
  static XdrSignerKey ed25519PublicKey(KeyPair keyPair) {
    checkNotNull(keyPair, "keyPair cannot be null");
    return keyPair.xdrSignerKey;
  }

  ///Create <code>sha256Hash</code> XdrSignerKey from
  ///a sha256 hash of a preimage.
  static XdrSignerKey sha256Hash(Uint8List hash) {
    checkNotNull(hash, "hash cannot be null");
    XdrSignerKey signerKey = new XdrSignerKey();
    XdrUint256 value = SignerKey._createUint256(hash);

    signerKey.discriminant = XdrSignerKeyType.SIGNER_KEY_TYPE_HASH_X;
    signerKey.hashX = value;

    return signerKey;
  }

  ///Create <code>preAuthTx</code> XdrSignerKey from
  ///a XdrTransaction hash.
  static XdrSignerKey preAuthTx(Transaction tx) {
    checkNotNull(tx, "tx cannot be null");
    XdrSignerKey signerKey = new XdrSignerKey();
    XdrUint256 value = SignerKey._createUint256(tx.hash());

    signerKey.discriminant = XdrSignerKeyType.SIGNER_KEY_TYPE_PRE_AUTH_TX;
    signerKey.preAuthTx = value;

    return signerKey;
  }

  ///Create <code>preAuthTx</code> XdrSignerKey from
  ///a transaction hash.
  static XdrSignerKey preAuthTxHash(Uint8List hash) {
    checkNotNull(hash, "hash cannot be null");
    XdrSignerKey signerKey = new XdrSignerKey();
    XdrUint256 value = SignerKey._createUint256(hash);

    signerKey.discriminant = XdrSignerKeyType.SIGNER_KEY_TYPE_PRE_AUTH_TX;
    signerKey.preAuthTx = value;

    return signerKey;
  }

  static XdrUint256 _createUint256(Uint8List hash) {
    if (hash.length != 32) {
      throw new Exception("hash must be 32 bytes long");
    }
    XdrUint256 value = new XdrUint256();
    value.uint256 = hash;
    return value;
  }
}
