# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL) && defined?(OpenSSL::PKey::EC)

class OpenSSL::TestEC < OpenSSL::PKeyTestCase
  def test_ec_key
    builtin_curves = OpenSSL::PKey::EC.builtin_curves
    assert_not_empty builtin_curves

    builtin_curves.each do |curve_name, comment|
      # Oakley curves and X25519 are not suitable for signing and causes
      # FIPS-selftest failure on some environment, so skip for now.
      next if ["Oakley", "X25519"].any? { |n| curve_name.start_with?(n) }

      key = OpenSSL::PKey::EC.new(curve_name)
      key.generate_key!

      assert_predicate key, :private?
      assert_predicate key, :public?
      assert_nothing_raised { key.check_key }
    end

    key1 = OpenSSL::PKey::EC.new("prime256v1").generate_key!

    key2 = OpenSSL::PKey::EC.new
    key2.group = key1.group
    key2.private_key = key1.private_key
    key2.public_key = key1.public_key
    assert_equal key1.to_der, key2.to_der

    key3 = OpenSSL::PKey::EC.new(key1)
    assert_equal key1.to_der, key3.to_der

    key4 = OpenSSL::PKey::EC.new(key1.to_der)
    assert_equal key1.to_der, key4.to_der

    key5 = key1.dup
    assert_equal key1.to_der, key5.to_der
    key_tmp = OpenSSL::PKey::EC.new("prime256v1").generate_key!
    key5.private_key = key_tmp.private_key
    key5.public_key = key_tmp.public_key
    assert_not_equal key1.to_der, key5.to_der
  end

  def test_generate
    assert_raise(OpenSSL::PKey::ECError) { OpenSSL::PKey::EC.generate("non-existent") }
    g = OpenSSL::PKey::EC::Group.new("prime256v1")
    ec = OpenSSL::PKey::EC.generate(g)
    assert_equal(true, ec.private?)
    ec = OpenSSL::PKey::EC.generate("prime256v1")
    assert_equal(true, ec.private?)
  end

  def test_marshal
    key = Fixtures.pkey("p256")
    deserialized = Marshal.load(Marshal.dump(key))

    assert_equal key.to_der, deserialized.to_der
  end

  def test_check_key
    key = OpenSSL::PKey::EC.new("prime256v1").generate_key!
    assert_equal(true, key.check_key)
    assert_equal(true, key.private?)
    assert_equal(true, key.public?)
    key2 = OpenSSL::PKey::EC.new(key.group)
    assert_equal(false, key2.private?)
    assert_equal(false, key2.public?)
    key2.public_key = key.public_key
    assert_equal(false, key2.private?)
    assert_equal(true, key2.public?)
    key2.private_key = key.private_key
    assert_equal(true, key2.private?)
    assert_equal(true, key2.public?)
    assert_equal(true, key2.check_key)
    key2.private_key += 1
    assert_raise(OpenSSL::PKey::ECError) { key2.check_key }
  end

  def test_sign_verify
    p256 = Fixtures.pkey("p256")
    data = "Sign me!"
    signature = p256.sign("SHA1", data)
    assert_equal true, p256.verify("SHA1", signature, data)

    signature0 = (<<~'end;').unpack("m")[0]
      MEQCIEOTY/hD7eI8a0qlzxkIt8LLZ8uwiaSfVbjX2dPAvN11AiAQdCYx56Fq
      QdBp1B4sxJoA8jvODMMklMyBKVmudboA6A==
    end;
    assert_equal true, p256.verify("SHA256", signature0, data)
    signature1 = signature0.succ
    assert_equal false, p256.verify("SHA256", signature1, data)
  end

  def test_derive_key
    # NIST CAVP, KAS_ECC_CDH_PrimitiveTest.txt, P-256 COUNT = 0
    qCAVSx = "700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287"
    qCAVSy = "db71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac"
    dIUT = "7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534"
    zIUT = "46fc62106420ff012e54a434fbdd2d25ccc5852060561e68040dd7778997bd7b"
    a = OpenSSL::PKey::EC.new("prime256v1")
    a.private_key = OpenSSL::BN.new(dIUT, 16)
    b = OpenSSL::PKey::EC.new("prime256v1")
    uncompressed = OpenSSL::BN.new("04" + qCAVSx + qCAVSy, 16)
    b.public_key = OpenSSL::PKey::EC::Point.new(b.group, uncompressed)
    assert_equal [zIUT].pack("H*"), a.derive(b)

    assert_equal a.derive(b), a.dh_compute_key(b.public_key)
  end

  def test_dsa_sign_verify
    data1 = "foo"
    data2 = "bar"
    key = OpenSSL::PKey::EC.new("prime256v1").generate_key!
    sig = key.dsa_sign_asn1(data1)
    assert_equal true, key.dsa_verify_asn1(data1, sig)
    assert_equal false, key.dsa_verify_asn1(data2, sig)
  end

  def test_dsa_sign_asn1_FIPS186_3
    key = OpenSSL::PKey::EC.new("prime256v1").generate_key!
    size = key.group.order.num_bits / 8 + 1
    dgst = (1..size).to_a.pack('C*')
    sig = key.dsa_sign_asn1(dgst)
    # dgst is auto-truncated according to FIPS186-3 after openssl-0.9.8m
    assert(key.dsa_verify_asn1(dgst + "garbage", sig))
  end

  def test_dh_compute_key
    key_a = OpenSSL::PKey::EC.new("prime256v1").generate_key!
    key_b = OpenSSL::PKey::EC.new(key_a.group).generate_key!

    pub_a = key_a.public_key
    pub_b = key_b.public_key
    a = key_a.dh_compute_key(pub_b)
    b = key_b.dh_compute_key(pub_a)
    assert_equal a, b
  end

  def test_ECPrivateKey
    p256 = Fixtures.pkey("p256")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(1),
      OpenSSL::ASN1::OctetString(p256.private_key.to_s(2)),
      OpenSSL::ASN1::ObjectId("prime256v1", 0, :EXPLICIT),
      OpenSSL::ASN1::BitString(p256.public_key.to_octet_string(:uncompressed),
                               1, :EXPLICIT)
    ])
    key = OpenSSL::PKey::EC.new(asn1.to_der)
    assert_predicate key, :private?
    assert_same_ec p256, key

    pem = <<~EOF
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIID49FDqcf1O1eO8saTgG70UbXQw9Fqwseliit2aWhH1oAoGCCqGSM49
    AwEHoUQDQgAEFglk2c+oVUIKQ64eZG9bhLNPWB7lSZ/ArK41eGy5wAzU/0G51Xtt
    CeBUl+MahZtn9fO1JKdF4qJmS39dXnpENg==
    -----END EC PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::EC.new(pem)
    assert_same_ec p256, key

    assert_equal asn1.to_der, p256.to_der
    assert_equal pem, p256.export
  end

  def test_ECPrivateKey_encrypted
    p256 = Fixtures.pkey("p256")
    # key = abcdef
    pem = <<~EOF
    -----BEGIN EC PRIVATE KEY-----
    Proc-Type: 4,ENCRYPTED
    DEK-Info: AES-128-CBC,85743EB6FAC9EA76BF99D9328AFD1A66

    nhsP1NHxb53aeZdzUe9umKKyr+OIwQq67eP0ONM6E1vFTIcjkDcFLR6PhPFufF4m
    y7E2HF+9uT1KPQhlE+D63i1m1Mvez6PWfNM34iOQp2vEhaoHHKlR3c43lLyzaZDI
    0/dGSU5SzFG+iT9iFXCwCvv+bxyegkBOyALFje1NAsM=
    -----END EC PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::EC.new(pem, "abcdef")
    assert_same_ec p256, key
    key = OpenSSL::PKey::EC.new(pem) { "abcdef" }
    assert_same_ec p256, key

    cipher = OpenSSL::Cipher.new("aes-128-cbc")
    exported = p256.to_pem(cipher, "abcdef\0\1")
    assert_same_ec p256, OpenSSL::PKey::EC.new(exported, "abcdef\0\1")
    assert_raise(OpenSSL::PKey::ECError) {
      OpenSSL::PKey::EC.new(exported, "abcdef")
    }
  end

  def test_PUBKEY
    p256 = Fixtures.pkey("p256")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::ObjectId("id-ecPublicKey"),
        OpenSSL::ASN1::ObjectId("prime256v1")
      ]),
      OpenSSL::ASN1::BitString(
        p256.public_key.to_octet_string(:uncompressed)
      )
    ])
    key = OpenSSL::PKey::EC.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_ec dup_public(p256), key

    pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEFglk2c+oVUIKQ64eZG9bhLNPWB7l
    SZ/ArK41eGy5wAzU/0G51XttCeBUl+MahZtn9fO1JKdF4qJmS39dXnpENg==
    -----END PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::EC.new(pem)
    assert_same_ec dup_public(p256), key

    assert_equal asn1.to_der, dup_public(p256).to_der
    assert_equal pem, dup_public(p256).export
  end

  def test_ec_group
    group1 = OpenSSL::PKey::EC::Group.new("prime256v1")
    key1 = OpenSSL::PKey::EC.new(group1)
    assert_equal group1, key1.group

    group2 = OpenSSL::PKey::EC::Group.new(group1)
    assert_equal group1.to_der, group2.to_der
    assert_equal group1, group2
    group2.asn1_flag ^=OpenSSL::PKey::EC::NAMED_CURVE
    assert_not_equal group1.to_der, group2.to_der
    assert_equal group1, group2

    group3 = group1.dup
    assert_equal group1.to_der, group3.to_der

    assert group1.asn1_flag & OpenSSL::PKey::EC::NAMED_CURVE # our default
    der = group1.to_der
    group4 = OpenSSL::PKey::EC::Group.new(der)
    group1.point_conversion_form = group4.point_conversion_form = :uncompressed
    assert_equal :uncompressed, group1.point_conversion_form
    assert_equal :uncompressed, group4.point_conversion_form
    assert_equal group1, group4
    assert_equal group1.curve_name, group4.curve_name
    assert_equal group1.generator.to_octet_string(:uncompressed),
      group4.generator.to_octet_string(:uncompressed)
    assert_equal group1.order, group4.order
    assert_equal group1.cofactor, group4.cofactor
    assert_equal group1.seed, group4.seed
    assert_equal group1.degree, group4.degree
  end

  def test_ec_point
    group = OpenSSL::PKey::EC::Group.new("prime256v1")
    key = OpenSSL::PKey::EC.new(group).generate_key!
    point = key.public_key

    point2 = OpenSSL::PKey::EC::Point.new(group, point.to_bn)
    assert_equal point, point2
    assert_equal point.to_bn, point2.to_bn
    assert_equal point.to_octet_string(:uncompressed),
      point2.to_octet_string(:uncompressed)

    point3 = OpenSSL::PKey::EC::Point.new(group,
                                          point.to_octet_string(:uncompressed))
    assert_equal point, point3
    assert_equal point.to_bn, point3.to_bn
    assert_equal point.to_octet_string(:uncompressed),
      point3.to_octet_string(:uncompressed)

    point2.invert!
    point3.invert!
    assert_not_equal point.to_octet_string(:uncompressed),
      point2.to_octet_string(:uncompressed)
    assert_equal point2.to_octet_string(:uncompressed),
      point3.to_octet_string(:uncompressed)

    begin
      group = OpenSSL::PKey::EC::Group.new(:GFp, 17, 2, 2)
      group.point_conversion_form = :uncompressed
      generator = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 05 01 }))
      group.set_generator(generator, 19, 1)
      point = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 06 03 }))
    rescue OpenSSL::PKey::EC::Group::Error
      pend "Patched OpenSSL rejected curve" if /unsupported field/ =~ $!.message
      raise
    end

    assert_equal 0x040603.to_bn, point.to_bn
    assert_equal 0x040603.to_bn, point.to_bn(:uncompressed)
    assert_equal 0x0306.to_bn, point.to_bn(:compressed)
    assert_equal 0x070603.to_bn, point.to_bn(:hybrid)

    group2 = group.dup; group2.point_conversion_form = :compressed
    point2 = OpenSSL::PKey::EC::Point.new(group2, B(%w{ 04 06 03 }))
    assert_equal 0x0306.to_bn, point2.to_bn

    assert_equal B(%w{ 04 06 03 }), point.to_octet_string(:uncompressed)
    assert_equal B(%w{ 03 06 }), point.to_octet_string(:compressed)
    assert_equal B(%w{ 07 06 03 }), point.to_octet_string(:hybrid)

    assert_equal true, point.on_curve?
    point.invert! # 8.5
    assert_equal B(%w{ 04 06 0E }), point.to_octet_string(:uncompressed)
    assert_equal true, point.on_curve?

    assert_equal false, point.infinity?
    point.set_to_infinity!
    assert_equal true, point.infinity?
    assert_equal 0.to_bn, point.to_bn
    assert_equal B(%w{ 00 }), point.to_octet_string(:uncompressed)
    assert_equal true, point.on_curve?
  end

  def test_ec_point_add
    begin
      group = OpenSSL::PKey::EC::Group.new(:GFp, 17, 2, 2)
      group.point_conversion_form = :uncompressed
      gen = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 05 01 }))
      group.set_generator(gen, 19, 1)

      point_a = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 06 03 }))
      point_b = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 10 0D }))
    rescue OpenSSL::PKey::EC::Group::Error
      pend "Patched OpenSSL rejected curve" if /unsupported field/ =~ $!.message
      raise
    end

    result = point_a.add(point_b)
    assert_equal B(%w{ 04 0D 07 }), result.to_octet_string(:uncompressed)

    assert_raise(TypeError) { point_a.add(nil) }
    assert_raise(ArgumentError) { point_a.add }
  end

  def test_ec_point_mul
    begin
      # y^2 = x^3 + 2x + 2 over F_17
      # generator is (5, 1)
      group = OpenSSL::PKey::EC::Group.new(:GFp, 17, 2, 2)
      group.point_conversion_form = :uncompressed
      gen = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 05 01 }))
      group.set_generator(gen, 19, 1)

      # 3 * (6, 3) = (16, 13)
      point_a = OpenSSL::PKey::EC::Point.new(group, B(%w{ 04 06 03 }))
      result_a1 = point_a.mul(3)
      assert_equal B(%w{ 04 10 0D }), result_a1.to_octet_string(:uncompressed)
      # 3 * (6, 3) + 3 * (5, 1) = (7, 6)
      result_a2 = point_a.mul(3, 3)
      assert_equal B(%w{ 04 07 06 }), result_a2.to_octet_string(:uncompressed)
      EnvUtil.suppress_warning do # Point#mul(ary, ary [, bn]) is deprecated
        begin
          result_b1 = point_a.mul([3], [])
        rescue NotImplementedError
          # LibreSSL and OpenSSL 3.0 do no longer support this form of calling
          next
        end

        # 3 * point_a = 3 * (6, 3) = (16, 13)
        result_b1 = point_a.mul([3], [])
        assert_equal B(%w{ 04 10 0D }), result_b1.to_octet_string(:uncompressed)
        # 3 * point_a + 2 * point_a = 3 * (6, 3) + 2 * (6, 3) = (7, 11)
        result_b1 = point_a.mul([3, 2], [point_a])
        assert_equal B(%w{ 04 07 0B }), result_b1.to_octet_string(:uncompressed)
        # 3 * point_a + 5 * point_a.group.generator = 3 * (6, 3) + 5 * (5, 1) = (13, 10)
        result_b1 = point_a.mul([3], [], 5)
        assert_equal B(%w{ 04 0D 0A }), result_b1.to_octet_string(:uncompressed)

        assert_raise(ArgumentError) { point_a.mul([1], [point_a]) }
        assert_raise(TypeError) { point_a.mul([1], nil) }
        assert_raise(TypeError) { point_a.mul([nil], []) }
      end
    rescue OpenSSL::PKey::EC::Group::Error
      # CentOS patches OpenSSL to reject curves defined over Fp where p < 256 bits
      raise if $!.message !~ /unsupported field/
    end

    p256_key = Fixtures.pkey("p256")
    p256_g = p256_key.group
    assert_equal(p256_key.public_key, p256_g.generator.mul(p256_key.private_key))

    # invalid argument
    point = p256_key.public_key
    assert_raise(TypeError) { point.mul(nil) }
  end

  def test_ecdsa_generate_from_k
    group = OpenSSL::PKey::EC::Group.new 'prime192v1'

    k = OpenSSL::BN.new '0758753A5254759C7CFBAD2E2D9B0792EEE44136C9480527', 16
    expected_r = OpenSSL::BN.new 'FE4F4AE86A58B6507946715934FE2D8FF9D95B6B098FE739', 16

    inverse_k, r = group.send(:ecdsa_generate_signature_params, k)

    assert_equal(expected_r, r)
    assert_not_equal(inverse_k, k)
    assert_equal(0.to_bn, group.order.mod_mul(inverse_k, group.order))
  end

  def test_ecdsa_deterministic_k
    group = OpenSSL::PKey::EC::Group.new 'prime192v1'

    private_key = OpenSSL::BN.new '6FAB034934E4C0FC9AE67F5B5659A9D7D1FEFD187EE09FD4', 16
    public_key_encoded = OpenSSL::BN.new '04AC2C77F529F91689FEA0EA5EFEC7F210D8EEA0B9E047ED56' \
                                 '3BC723E57670BD4887EBC732C523063D0A7C957BC97C1C43', 16
    public_key = OpenSSL::PKey::EC::Point.new group, public_key_encoded
    key = OpenSSL::PKey::EC.new group
    key.private_key = private_key
    key.public_key = public_key

    hash = OpenSSL::Digest.new('SHA512').digest('test')

    k = OpenSSL::BN.new '0758753A5254759C7CFBAD2E2D9B0792EEE44136C9480527', 16
    expected_r = OpenSSL::BN.new 'FE4F4AE86A58B6507946715934FE2D8FF9D95B6B098FE739', 16
    expected_s = OpenSSL::BN.new '74CF5605C98FBA0E1EF34D4B5A1577A7DCF59457CAE52290', 16

    inverse_k, r = group.send(:ecdsa_generate_signature_params, k)

    result = key.dsa_sign_asn1(hash, inverse_k, r)
    assert_equal(true, key.dsa_verify_asn1(hash, result))

    k_only_result = key.dsa_sign_asn1(hash, k)
    assert_equal(true, key.dsa_verify_asn1(hash, k_only_result))

    parsed_signature = OpenSSL::ASN1.decode(result)
    assert_equal(expected_r, parsed_signature.value[0].value)
    assert_equal(expected_s, parsed_signature.value[1].value)
  end

# test Group: asn1_flag, point_conversion

  private

  def B(ary)
    [Array(ary).join].pack("H*")
  end

  def assert_same_ec(expected, key)
    check_component(expected, key, [:group, :public_key, :private_key])
  end
end

end
