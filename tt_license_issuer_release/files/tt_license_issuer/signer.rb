# encoding: UTF-8
require 'openssl'
require 'base64'
require 'json'
require 'digest'
require 'securerandom'
require 'time'

module TTLicenseIssuer
  module Signer
    extend self

    VERSION = '1.0.0'.freeze
    LICENSE_SCHEMA = 'TT_OFFLINE_RSA_V2'.freeze
    LICENSE_PREFIX = 'TTRSA2'.freeze
    RSA_ALGORITHM = 'RS256'.freeze
    RSA_KEY_ID = 'tt-offline-rsa-20260917'.freeze
    EXPECTED_PUBLIC_FINGERPRINT = '33c04cf83b7d0a85e842d210854ffef499001a90c7ecd93681bc5f58e263ddc6'.freeze

    PLANS = {
      '90d' => { 'label' => '90 ngày', 'days' => 90, 'price_vnd' => 50_000 },
      '180d' => { 'label' => '180 ngày', 'days' => 180, 'price_vnd' => 100_000 },
      '360d' => { 'label' => '360 ngày', 'days' => 360, 'price_vnd' => 120_000 },
      'lifetime' => { 'label' => 'Vĩnh viễn', 'days' => nil, 'price_vnd' => 200_000 }
    }.freeze

    MACHINE_PATTERN = /\ATT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}\z/.freeze

    def normalize_machine_code(text)
      code = text.to_s.strip.upcase.gsub(/\s+/, '')
      raise 'Mã máy không đúng định dạng TT-XXXX-XXXX-XXXX.' unless code.match?(MACHINE_PATTERN)
      code
    end

    def public_fingerprint(key)
      Digest::SHA256.hexdigest(key.public_key.to_der)
    end

    def load_private_key(path, expected_fingerprint: EXPECTED_PUBLIC_FINGERPRINT)
      full = File.expand_path(path.to_s)
      raise 'Chưa chọn file khóa riêng RSA.' if full.empty? || !File.file?(full)
      pem = File.binread(full)
      raise 'File đã chọn không phải khóa riêng RSA.' unless pem.include?('PRIVATE KEY')
      key = OpenSSL::PKey::RSA.new(pem)
      raise 'File không chứa private key.' unless key.private?
      fingerprint = public_fingerprint(key)
      unless expected_fingerprint.to_s.empty? || fingerprint == expected_fingerprint.to_s.downcase
        raise "Khóa RSA không khớp hệ thống TRẦN TUẤN hiện tại. Fingerprint: #{fingerprint}"
      end
      key
    rescue OpenSSL::PKey::PKeyError => error
      raise "Không đọc được khóa RSA: #{error.message}"
    end

    def b64url(data)
      Base64.urlsafe_encode64(data, padding: false)
    end

    def generate(machine_code, plan, key, now: Time.now, expected_fingerprint: EXPECTED_PUBLIC_FINGERPRINT)
      machine = normalize_machine_code(machine_code)
      plan_id = plan.to_s.strip
      info = PLANS[plan_id]
      raise 'Thời hạn bản quyền không hợp lệ.' unless info
      raise 'Private key không hợp lệ.' unless key.is_a?(OpenSSL::PKey::RSA) && key.private?

      fingerprint = public_fingerprint(key)
      unless expected_fingerprint.to_s.empty? || fingerprint == expected_fingerprint.to_s.downcase
        raise 'Private key không khớp public key của plugin khách.'
      end

      issued_at = now.utc
      expires_at = info['days'] ? (issued_at + info['days'].to_i * 86_400).utc : nil
      license_id = "TTLIC-#{issued_at.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4).upcase}"

      payload = {
        'schema' => LICENSE_SCHEMA,
        'alg' => RSA_ALGORITHM,
        'key_id' => RSA_KEY_ID,
        'license_id' => license_id,
        'machine_code' => machine,
        'plan' => plan_id,
        'issued_at' => issued_at.iso8601,
        'expires_at' => expires_at ? expires_at.iso8601 : nil
      }

      raw = JSON.generate(payload)
      signature = key.sign(OpenSSL::Digest::SHA256.new, raw)
      activation_code = "#{LICENSE_PREFIX}.#{b64url(raw)}.#{b64url(signature)}"

      {
        'ok' => true,
        'activation_code' => activation_code,
        'license_id' => license_id,
        'machine_code' => machine,
        'plan' => plan_id,
        'plan_label' => info['label'],
        'price_vnd' => info['price_vnd'],
        'issued_at' => issued_at.iso8601,
        'expires_at' => expires_at ? expires_at.iso8601 : nil,
        'lifetime' => plan_id == 'lifetime',
        'fingerprint' => fingerprint
      }
    end
  end
end
