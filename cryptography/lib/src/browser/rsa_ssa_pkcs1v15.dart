// Copyright 2019-2020 Gohilla.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

import '_javascript_bindings.dart' as web_crypto;
import '_javascript_bindings.dart' show base64UrlDecodeUnmodifiable, base64UrlEncode, base64UrlEncodeMaybe;
import 'hash.dart';

/// RSA-SSA-PKCS1v15 implementation that uses _Web Cryptography API_ in browsers.
///
/// See [BrowserCryptography].
class BrowserRsaSsaPkcs1v15 extends RsaSsaPkcs1v15 {
  static const _webCryptoAlgorithm = 'RSASSA-PKCS1-v1_5';

  @override
  final BrowserHashAlgorithmMixin hashAlgorithm;

  const BrowserRsaSsaPkcs1v15(
    this.hashAlgorithm, {
    Random? random,
  }) : super.constructor();

  String get webCryptoHash {
    final h = hashAlgorithm;
    if (h is Sha1) {
      return 'SHA-1';
    }
    if (h is Sha256) {
      return 'SHA-256';
    }
    if (h is Sha384) {
      return 'SHA-384';
    }
    if (h is Sha512) {
      return 'SHA-512';
    }
    throw StateError(
      'Hash function not supported by Web Cryptography API: $hashAlgorithm',
    );
  }

  @override
  Future<RsaKeyPair> newKeyPair({
    int modulusLength = RsaSsaPkcs1v15.defaultModulusLength,
    List<int> publicExponent = RsaSsaPkcs1v15.defaultPublicExponent,
  }) async {
    // Generate CryptoKeyPair
    final jsCryptoKeyPair = await web_crypto.generateKeyWhenKeyPair(
      web_crypto.RsaHashedKeyGenParams(
        name: _webCryptoAlgorithm,
        modulusLength: modulusLength,
        publicExponent: Uint8List.fromList(publicExponent),
        hash: webCryptoHash,
      ),
      true,
      ['sign', 'verify'],
    );
    return _BrowserRsaSsaPkcs1v15KeyPair(
      jsCryptoKeyPair,
      webCryptoAlgorithm: _webCryptoAlgorithm,
      webCryptoHash: webCryptoHash,
    );
  }

  @override
  Future<Signature> sign(List<int> message, {required KeyPair keyPair}) async {
    final keyPairData = await keyPair.extract();
    if (keyPairData is! RsaKeyPairData) {
      throw ArgumentError.value(
        keyPair,
        'keyPair',
        'Should be an instance of RsaKeyPair',
      );
    }
    final publicKeyFuture = keyPairData.extractPublicKey();
    final jsCryptoKey = await _jsCryptoKeyFromRsaKeyPair(
      keyPairData,
      webCryptoAlgorithm: _webCryptoAlgorithm,
      webCryptoHash: webCryptoHash,
    );
    final byteBuffer = await web_crypto.sign(
      _webCryptoAlgorithm,
      jsCryptoKey,
      web_crypto.jsArrayBufferFrom(message),
    );
    return Signature(
      Uint8List.view(byteBuffer),
      publicKey: await publicKeyFuture,
    );
  }

  @override
  Future<bool> verify(List<int> message, {required Signature signature}) async {
    final publicKey = signature.publicKey;
    if (publicKey is! RsaPublicKey) {
      throw ArgumentError.value(
        signature,
        'signature',
        'Public key should be an instance of RsaPublicKey, not: $publicKey',
      );
    }
    final jsCryptoKey = await _jsCryptoKeyFromRsaPublicKey(
      signature.publicKey,
      webCryptoAlgorithm: _webCryptoAlgorithm,
      webCryptoHash: webCryptoHash,
    );
    return await web_crypto.verify(
      _webCryptoAlgorithm,
      jsCryptoKey,
      web_crypto.jsArrayBufferFrom(signature.bytes),
      web_crypto.jsArrayBufferFrom(message),
    );
  }

  Future<web_crypto.CryptoKey> _jsCryptoKeyFromRsaKeyPair(
    KeyPair keyPair, {
    required String webCryptoAlgorithm,
    required String webCryptoHash,
  }) async {
    if (keyPair is _BrowserRsaSsaPkcs1v15KeyPair &&
        keyPair.webCryptoAlgorithm == webCryptoAlgorithm &&
        keyPair.webCryptoHash == webCryptoHash) {
      return keyPair.jsCryptoKeyPair.privateKey;
    }
    final keyPairData = await keyPair.extract() as RsaKeyPairData;
    if (!KeyPairType.rsa.isValidKeyPairData(keyPairData)) {
      throw ArgumentError.value(
        keyPair,
        'keyPair',
      );
    }
    // Import JWK key
    return web_crypto.importKeyWhenJwk(
      web_crypto.Jwk(
        kty: 'RSA',
        n: base64UrlEncode(keyPairData.n),
        e: base64UrlEncode(keyPairData.e),
        p: base64UrlEncode(keyPairData.p),
        d: base64UrlEncode(keyPairData.d),
        q: base64UrlEncode(keyPairData.q),
        dp: base64UrlEncodeMaybe(keyPairData.dp),
        dq: base64UrlEncodeMaybe(keyPairData.dq),
        qi: base64UrlEncodeMaybe(keyPairData.qi),
      ),
      web_crypto.RsaHashedImportParams(
        name: webCryptoAlgorithm,
        hash: webCryptoHash,
      ),
      false,
      const ['sign'],
    );
  }

  Future<web_crypto.CryptoKey> _jsCryptoKeyFromRsaPublicKey(
    PublicKey publicKey, {
    required String webCryptoAlgorithm,
    required String webCryptoHash,
  }) async {
    if (publicKey is _BrowserRsaPublicKey &&
        webCryptoAlgorithm == publicKey.webCryptoAlgorithm &&
        webCryptoHash == publicKey.webCryptoHash) {
      return publicKey.jsCryptoKey;
    }
    if (publicKey is! RsaPublicKey) {
      throw ArgumentError.value(
        publicKey,
        'publicKey',
        'Should be RsaPublicKey',
      );
    }
    return web_crypto.importKeyWhenJwk(
      web_crypto.Jwk(
        kty: 'RSA',
        n: base64UrlEncode(publicKey.n),
        e: base64UrlEncode(publicKey.e),
      ),
      web_crypto.RsaHashedImportParams(
        name: webCryptoAlgorithm,
        hash: webCryptoHash,
      ),
      false,
      const ['verify'],
    );
  }
}

class _BrowserRsaPublicKey extends RsaPublicKey {
  final web_crypto.CryptoKey jsCryptoKey;
  final String webCryptoAlgorithm;
  final String webCryptoHash;

  _BrowserRsaPublicKey({
    required this.jsCryptoKey,
    required this.webCryptoAlgorithm,
    required this.webCryptoHash,
    required super.n,
    required super.e,
  });
}

class _BrowserRsaSsaPkcs1v15KeyPair extends KeyPair implements RsaKeyPair {
  final web_crypto.CryptoKeyPair jsCryptoKeyPair;
  final String webCryptoAlgorithm;
  final String webCryptoHash;

  _BrowserRsaSsaPkcs1v15KeyPair(
    this.jsCryptoKeyPair, {
    required this.webCryptoAlgorithm,
    required this.webCryptoHash,
  });

  @override
  Future<RsaKeyPairData> extract() async {
    final jsJwk = await web_crypto.exportKeyWhenJwk(
      jsCryptoKeyPair.privateKey,
    );
    return RsaKeyPairData(
      n: web_crypto.base64UrlDecodeUnmodifiable(jsJwk.n!),
      e: web_crypto.base64UrlDecodeUnmodifiable(jsJwk.e!),
      d: web_crypto.base64UrlDecodeUnmodifiable(jsJwk.d!),
      p: web_crypto.base64UrlDecodeUnmodifiable(jsJwk.p!),
      q: web_crypto.base64UrlDecodeUnmodifiable(jsJwk.q!),
      dp: web_crypto.base64UrlDecodeUnmodifiableMaybe(jsJwk.dp),
      dq: web_crypto.base64UrlDecodeUnmodifiableMaybe(jsJwk.dq),
      qi: web_crypto.base64UrlDecodeUnmodifiableMaybe(jsJwk.qi),
    );
  }

  @override
  Future<RsaPublicKey> extractPublicKey() async {
    final jsJwk = await web_crypto.exportKeyWhenJwk(
      jsCryptoKeyPair.publicKey,
    );
    return _BrowserRsaPublicKey(
      jsCryptoKey: jsCryptoKeyPair.publicKey,
      webCryptoAlgorithm: webCryptoAlgorithm,
      webCryptoHash: webCryptoHash,
      n: base64UrlDecodeUnmodifiable(jsJwk.n!),
      e: base64UrlDecodeUnmodifiable(jsJwk.e!),
    );
  }
}
