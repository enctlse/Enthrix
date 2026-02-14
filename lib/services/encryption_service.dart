import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';


class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;
  bool _usePrefs = false;


  Map<String, RSAPublicKey> _publicKeys = {};


  String? _currentUserId;
  RSAPublicKey? _myPublicKey;
  RSAPrivateKey? _myPrivateKey;


  Future<void> _initStorage() async {
    if (_prefs == null) {
      try {
        _prefs = await SharedPreferences.getInstance();

        await _secureStorage.write(key: 'test_key', value: 'test');
        await _secureStorage.delete(key: 'test_key');
      } catch (e) {
        print('EncryptionService: Secure storage not available, using SharedPreferences');
        _usePrefs = true;
      }
    }
  }

 
  Future<void> initialize(String userId) async {
    _currentUserId = userId;
    
    await _initStorage();

    final existingKeys = await _loadKeysFromStorage(userId);
    
    if (existingKeys != null) {
      _myPublicKey = existingKeys.publicKey;
      _myPrivateKey = existingKeys.privateKey;
      print('EncryptionService: Loaded existing keys for user $userId');
    } else {
      final keyPair = _generateRSAKeyPair();
      _myPublicKey = keyPair.publicKey;
      _myPrivateKey = keyPair.privateKey;
      
      await _saveKeysToStorage(userId, _myPublicKey!, _myPrivateKey!);
      print('EncryptionService: Generated and saved new keys for user $userId');
    }
  }

  Future<String?> _readValue(String key) async {
    try {
      if (_usePrefs && _prefs != null) {
        return _prefs!.getString(key);
      }
      return await _secureStorage.read(key: key);
    } catch (e) {
      if (_prefs != null) {
        _usePrefs = true;
        return _prefs!.getString(key);
      }
      return null;
    }
  }

  Future<void> _writeValue(String key, String value) async {
    try {
      if (_usePrefs && _prefs != null) {
        await _prefs!.setString(key, value);
        return;
      }
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      if (_prefs != null) {
        _usePrefs = true;
        await _prefs!.setString(key, value);
      }
    }
  }

  Future<void> _deleteValue(String key) async {
    try {
      if (_usePrefs && _prefs != null) {
        await _prefs!.remove(key);
        return;
      }
      await _secureStorage.delete(key: key);
    } catch (e) {
      if (_prefs != null) {
        _usePrefs = true;
        await _prefs!.remove(key);
      }
    }
  }

  Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>?> _loadKeysFromStorage(String userId) async {
    try {
      final publicKeyMod = await _readValue('${userId}_public_mod');
      final publicKeyExp = await _readValue('${userId}_public_exp');
      final privateKeyMod = await _readValue('${userId}_private_mod');
      final privateKeyExp = await _readValue('${userId}_private_exp');
      final privateKeyP = await _readValue('${userId}_private_p');
      final privateKeyQ = await _readValue('${userId}_private_q');

      if (publicKeyMod != null && publicKeyExp != null && 
          privateKeyMod != null && privateKeyExp != null &&
          privateKeyP != null && privateKeyQ != null) {
        final publicKey = RSAPublicKey(
          BigInt.parse(publicKeyMod),
          BigInt.parse(publicKeyExp),
        );
        final privateKey = RSAPrivateKey(
          BigInt.parse(privateKeyMod),
          BigInt.parse(privateKeyExp),
          BigInt.parse(privateKeyP),
          BigInt.parse(privateKeyQ),
        );
        return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(publicKey, privateKey);
      }
    } catch (e) {
      print('EncryptionService: Error loading keys from storage: $e');
    }
    return null;
  }

  Future<void> _saveKeysToStorage(String userId, RSAPublicKey publicKey, RSAPrivateKey privateKey) async {
    try {
      await _writeValue('${userId}_public_mod', publicKey.modulus.toString());
      await _writeValue('${userId}_public_exp', publicKey.publicExponent.toString());
      await _writeValue('${userId}_private_mod', privateKey.modulus.toString());
      await _writeValue('${userId}_private_exp', privateKey.privateExponent.toString());
      await _writeValue('${userId}_private_p', privateKey.p.toString());
      await _writeValue('${userId}_private_q', privateKey.q.toString());
      print('EncryptionService: Keys saved to ${_usePrefs ? "SharedPreferences" : "secure storage"}');
    } catch (e) {
      print('EncryptionService: Error saving keys to storage: $e');
    }
  }

  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ),
      );

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  String getPublicKeyString() {
    if (_myPublicKey == null) throw Exception('Encryption not initialized');

    final mod = _myPublicKey!.modulus.toString();
    final exp = _myPublicKey!.publicExponent.toString();
    return base64Encode(utf8.encode('$mod:$exp'));
  }

  void importPublicKey(String userId, String publicKeyString) {
    try {
      final decoded = utf8.decode(base64Decode(publicKeyString));
      final parts = decoded.split(':');
      if (parts.length != 2) throw Exception('Invalid public key format');

      final mod = BigInt.parse(parts[0]);
      final exp = BigInt.parse(parts[1]);

      _publicKeys[userId] = RSAPublicKey(mod, exp);
    } catch (e) {
      print('Error importing public key: $e');
    }
  }

  bool hasPublicKey(String userId) {
    return _publicKeys.containsKey(userId);
  }

  String encryptMessage(String recipientId, String plainText) {
    final recipientPublicKey = _publicKeys[recipientId];
    if (recipientPublicKey == null) {
      throw Exception('Public key not found for user $recipientId');
    }

    try {
      final aesKey = _generateAESKey();

      final aesEncrypted = _encryptWithAES(plainText, aesKey);

      final rsaEncrypted = _encryptWithRSA(aesKey, recipientPublicKey);

      final combined = {
        'key': base64Encode(rsaEncrypted),
        'data': base64Encode(aesEncrypted),
      };

      return base64Encode(utf8.encode(jsonEncode(combined)));
    } catch (e) {
      print('Encryption error: $e');
      throw Exception('Failed to encrypt message');
    }
  }

  String decryptMessage(String encryptedData) {
    if (_myPrivateKey == null) {
      throw Exception('Private key not available');
    }

    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encryptedData)));
      final encryptedKey = base64Decode(decoded['key']);
      final encryptedMessage = base64Decode(decoded['data']);

      final aesKey = _decryptWithRSA(encryptedKey, _myPrivateKey!);

      final plainText = _decryptWithAES(encryptedMessage, aesKey);

      return plainText;
    } catch (e) {
      print('Decryption error: $e');
      throw Exception('Failed to decrypt message');
    }
  }

  Uint8List _generateAESKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  Uint8List _encryptWithAES(String plainText, Uint8List key) {
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final result = Uint8List(iv.bytes.length + encrypted.bytes.length);
    result.setRange(0, iv.bytes.length, iv.bytes);
    result.setRange(iv.bytes.length, result.length, encrypted.bytes);

    return result;
  }

  String _decryptWithAES(Uint8List encryptedData, Uint8List key) {
    final iv = encrypt.IV(Uint8List.sublistView(encryptedData, 0, 16));
    final encrypted = Uint8List.sublistView(encryptedData, 16);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
    );

    return encrypter.decrypt64(base64Encode(encrypted), iv: iv);
  }

  Uint8List _encryptWithRSA(Uint8List data, RSAPublicKey publicKey) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    return _processInBlocks(encryptor, data);
  }

  Uint8List _decryptWithRSA(Uint8List data, RSAPrivateKey privateKey) {
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    return _processInBlocks(decryptor, data);
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List data) {
    final numBlocks = (data.length / engine.inputBlockSize).ceil();
    final output = <int>[];

    for (var i = 0; i < numBlocks; i++) {
      final start = i * engine.inputBlockSize;
      final end = (start + engine.inputBlockSize < data.length)
          ? start + engine.inputBlockSize
          : data.length;

      final block = Uint8List.sublistView(data, start, end);
      output.addAll(engine.process(block));
    }

    return Uint8List.fromList(output);
  }

  Future<void> clearKeys({bool deleteFromStorage = false}) async {
    _publicKeys.clear();
    _myPublicKey = null;
    _myPrivateKey = null;
    
    if (deleteFromStorage && _currentUserId != null) {
      await _deleteKeysFromStorage(_currentUserId!);
    }
    
    _currentUserId = null;
  }

  Future<void> _deleteKeysFromStorage(String userId) async {
    try {
      await _deleteValue('${userId}_public_mod');
      await _deleteValue('${userId}_public_exp');
      await _deleteValue('${userId}_private_mod');
      await _deleteValue('${userId}_private_exp');
      await _deleteValue('${userId}_private_p');
      await _deleteValue('${userId}_private_q');
      print('EncryptionService: Keys deleted from storage');
    } catch (e) {
      print('EncryptionService: Error deleting keys from storage: $e');
    }
  }

  void clearMemoryKeys() {
    _publicKeys.clear();
    _myPublicKey = null;
    _myPrivateKey = null;
    _currentUserId = null;
  }
}


final encryptionService = EncryptionService();
