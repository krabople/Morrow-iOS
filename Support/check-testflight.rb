require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

ISSUER_ID = ENV.fetch("APPSTORE_ISSUER_ID")
KEY_ID = ENV.fetch("APPSTORE_KEY_ID")
PRIVATE_KEY = ENV.fetch("APPSTORE_PRIVATE_KEY")
APP_ID = ENV.fetch("APP_STORE_APP_ID")
BUILD_NUMBER = ENV.fetch("BUILD_NUMBER")

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def fixed_width(value)
  [value.to_i.to_s(16).rjust(64, "0")].pack("H*")
end

def token
  now = Time.now.to_i
  header = base64url({ alg: "ES256", kid: KEY_ID, typ: "JWT" }.to_json)
  payload = base64url({ iss: ISSUER_ID, iat: now, exp: now + 900, aud: "appstoreconnect-v1" }.to_json)
  unsigned = "#{header}.#{payload}"
  key = OpenSSL::PKey.read(PRIVATE_KEY)
  signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(unsigned))
  parts = OpenSSL::ASN1.decode(signature).value
  "#{unsigned}.#{base64url(parts.map { |part| fixed_width(part.value) }.join)}"
end

def fetch_build
  uri = URI("https://api.appstoreconnect.apple.com/v1/builds")
  uri.query = URI.encode_www_form(
    "filter[app]" => APP_ID,
    "filter[version]" => BUILD_NUMBER,
    "fields[builds]" => "version,processingState,uploadedDate,expired",
    "limit" => "5"
  )
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  abort "App Store Connect returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body).fetch("data").first
end

20.times do |attempt|
  build = fetch_build
  if build
    attributes = build.fetch("attributes")
    state = attributes.fetch("processingState")
    puts "Apple reports build #{BUILD_NUMBER} as #{state}."
    exit 0 if state == "VALID"
    abort "Apple rejected build #{BUILD_NUMBER} during processing." if %w[FAILED INVALID].include?(state)
  else
    puts "Waiting for build #{BUILD_NUMBER} to appear (attempt #{attempt + 1}/20)."
  end
  sleep 60
end

abort "Timed out waiting for Apple to finish processing build #{BUILD_NUMBER}."
