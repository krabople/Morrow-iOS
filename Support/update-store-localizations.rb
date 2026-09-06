require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

APP_ID = ENV.fetch("APP_STORE_APP_ID", "6809041904")
VERSION_STRING = ENV.fetch("APP_STORE_VERSION", "1.3.0")
API_BASE = "https://api.appstoreconnect.apple.com"
PRIVACY_URL = "https://github.com/krabople/Morrow-iOS/blob/main/PRIVACY.md"
SUPPORT_URL = "https://github.com/krabople/Morrow-iOS/blob/main/SUPPORT.md"
EDITABLE_STATES = %w[
  PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY
].freeze

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def fixed_width(value)
  [value.to_i.to_s(16).rjust(64, "0")].pack("H*")
end

def authorization_token
  now = Time.now.to_i
  header = base64url({ alg: "ES256", kid: ENV.fetch("APPSTORE_KEY_ID"), typ: "JWT" }.to_json)
  payload = base64url(
    { iss: ENV.fetch("APPSTORE_ISSUER_ID"), iat: now, exp: now + 900, aud: "appstoreconnect-v1" }.to_json
  )
  unsigned = "#{header}.#{payload}"
  key = OpenSSL::PKey.read(ENV.fetch("APPSTORE_PRIVATE_KEY"))
  signature = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(unsigned))
  parts = OpenSSL::ASN1.decode(signature).value
  "#{unsigned}.#{base64url(parts.map { |part| fixed_width(part.value) }.join)}"
end

def api_request(method, path, body = nil)
  uri = URI("#{API_BASE}#{path}")
  request_class = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post,
    patch: Net::HTTP::Patch
  }.fetch(method)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{authorization_token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  return parsed if response.code.to_i.between?(200, 299)

  warn JSON.pretty_generate(parsed)
  abort "App Store Connect API #{method.to_s.upcase} #{path} failed with HTTP #{response.code}"
end

def create_resource(type, attributes, relationship_name, related_type, relationship_id)
  api_request(
    :post,
    "/v1/#{type}",
    {
      data: {
        type: type,
        attributes: attributes,
        relationships: {
          relationship_name => { data: { type: related_type, id: relationship_id } }
        }
      }
    }
  ).fetch("data")
end

def update_resource(type, id, attributes)
  api_request(
    :patch,
    "/v1/#{type}/#{id}",
    { data: { type: type, id: id, attributes: attributes } }
  ).fetch("data")
end

copy = JSON.parse(File.read(File.join(__dir__, "store-localizations.json"))).fetch("languages")
localizations = copy.flat_map do |language|
  language.fetch("locales").map do |locale|
    language.merge("locale" => locale).reject { |key, _| key == "locales" }
  end
end

localizations.each do |item|
  abort "Subtitle too long for #{item['locale']}" if item.fetch("subtitle").length > 30
  abort "Promotional text too long for #{item['locale']}" if item.fetch("promotionalText").length > 170
  abort "Keywords exceed 100 bytes for #{item['locale']}" if item.fetch("keywords").bytesize > 100
end

app_info = api_request(:get, "/v1/apps/#{APP_ID}/appInfos?limit=10").fetch("data").first
abort "No App Info record exists for app #{APP_ID}" unless app_info
app_info_id = app_info.fetch("id")

existing_app_info = api_request(
  :get,
  "/v1/appInfos/#{app_info_id}/appInfoLocalizations?limit=200"
).fetch("data")
existing_app_info_by_locale = existing_app_info.to_h { |item| [item.dig("attributes", "locale"), item] }
existing_privacy_url = existing_app_info.filter_map { |item| item.dig("attributes", "privacyPolicyUrl") }.first
privacy_url = existing_privacy_url.to_s.empty? ? PRIVACY_URL : existing_privacy_url

versions = api_request(
  :get,
  "/v1/apps/#{APP_ID}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=200"
).fetch("data")
version = versions.find { |item| EDITABLE_STATES.include?(item.dig("attributes", "appStoreState")) }

unless version
  version = create_resource(
    "appStoreVersions",
    { versionString: VERSION_STRING, platform: "IOS" },
    "app",
    "apps",
    APP_ID
  )
  puts "Created editable iOS App Store version #{VERSION_STRING}"
end

version_id = version.fetch("id")
version_name = version.dig("attributes", "versionString") || VERSION_STRING
existing_version = api_request(
  :get,
  "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=200"
).fetch("data")
existing_version_by_locale = existing_version.to_h { |item| [item.dig("attributes", "locale"), item] }

localizations.each do |item|
  locale = item.fetch("locale")
  info_attributes = {
    name: "Listello",
    subtitle: item.fetch("subtitle"),
    privacyPolicyUrl: privacy_url
  }

  if (existing = existing_app_info_by_locale[locale])
    update_resource("appInfoLocalizations", existing.fetch("id"), info_attributes)
    print "Updated"
  else
    create_resource(
      "appInfoLocalizations",
      info_attributes.merge(locale: locale),
      "appInfo",
      "appInfos",
      app_info_id
    )
    print "Created"
  end
  puts " App Info: #{locale}"

  version_attributes = {
    description: item.fetch("description"),
    keywords: item.fetch("keywords"),
    promotionalText: item.fetch("promotionalText"),
    supportUrl: SUPPORT_URL
  }

  if (existing = existing_version_by_locale[locale])
    update_resource("appStoreVersionLocalizations", existing.fetch("id"), version_attributes)
    print "Updated"
  else
    create_resource(
      "appStoreVersionLocalizations",
      version_attributes.merge(locale: locale),
      "appStoreVersion",
      "appStoreVersions",
      version_id
    )
    print "Created"
  end
  puts " version metadata: #{locale}"
end

puts "Localized App Store version #{version_name} in #{localizations.length} locales."
