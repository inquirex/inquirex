# frozen_string_literal: true

require "net/http"

RSpec.describe Inquirex::Actions::Webhook do
  subject(:effect) { described_class.new(url: "https://crm.agentica.group/leads") }

  it { is_expected.to be_serializable }
  it { is_expected.to be_frozen }

  its(:host)    { is_expected.to eq("crm.agentica.group") }
  its(:timeout) { is_expected.to eq(described_class::DEFAULT_TIMEOUT) }

  describe "structural URL validation" do
    it "rejects plain http for non-local hosts" do
      expect { described_class.new(url: "http://crm.agentica.group/leads") }
        .to raise_error(Inquirex::Errors::DefinitionError, /must use https/)
    end

    it "allows plain http for localhost development" do
      expect(described_class.new(url: "http://localhost:3000/dev").host).to eq("localhost")
    end

    it "rejects userinfo smuggling" do
      expect { described_class.new(url: "https://user@evil.com/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /userinfo/)
    end

    it "rejects {{field}} templates in the url" do
      expect { described_class.new(url: "https://{{host}}/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /templates/)
    end

    it "rejects non-http schemes" do
      expect { described_class.new(url: "ftp://files.example.com/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /http/)
    end

    it "rejects host-less strings" do
      expect { described_class.new(url: "not a url") }
        .to raise_error(Inquirex::Errors::DefinitionError)
    end
  end

  describe "#call" do
    subject(:call) { effect.call(answers, nil) }

    let(:effect) do
      described_class.new(
        url:     "https://crm.agentica.group/leads",
        headers: { "X-Api-Key" => "secret" }
      )
    end
    let(:answers)  { Inquirex::Answers.new(name: "Ada", business: { count: 3 }) }
    let(:http)     { instance_double(Net::HTTP) }
    let(:response) { instance_double(Net::HTTPResponse, code: "201") }
    let(:requests) { [] }

    before do
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        block.call(http)
      end
      allow(http).to receive(:request) { |request| requests << request; response }
    end

    it "POSTs the answers envelope as JSON" do
      call
      request = requests.first
      expect(request.method).to eq("POST")
      expect(request.path).to eq("/leads")
      expect(request["Content-Type"]).to eq("application/json")
      expect(request["X-Api-Key"]).to eq("secret")
      expect(JSON.parse(request.body)).to eq(
        "answers" => { "name" => "Ada", "business" => { "count" => 3 } }
      )
    end

    it "uses TLS with the configured timeout" do
      call
      expect(Net::HTTP).to have_received(:start).with(
        "crm.agentica.group",
        443,
        use_ssl:      true,
        open_timeout: 10,
        read_timeout: 10
      )
    end

    context "when the endpoint responds non-2xx" do
      let(:response) { instance_double(Net::HTTPResponse, code: "503") }

      it "raises ActionError" do
        expect { call }.to raise_error(Inquirex::Errors::ActionError, /HTTP 503/)
      end
    end
  end

  describe "allowed_domains enforcement" do
    def define_flow(domains:, url:)
      Inquirex.define id: "hooked" do
        allowed_domains(*domains)
        start :email
        ask(:email) { type(:email); question("Email?") }
        action(:push) { webhook url: url }
      end
    end

    it "accepts a webhook whose host is listed exactly" do
      expect(define_flow(domains: ["crm.agentica.group"], url: "https://crm.agentica.group/x"))
        .to be_a(Inquirex::Definition)
    end

    it "accepts subdomains via wildcard entries" do
      expect(define_flow(domains: ["*.agentica.group"], url: "https://hooks.agentica.group/x"))
        .to be_a(Inquirex::Definition)
    end

    it "does not let a wildcard cover the apex domain" do
      expect { define_flow(domains: ["*.agentica.group"], url: "https://agentica.group/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /not covered by allowed_domains/)
    end

    it "rejects unlisted hosts" do
      expect { define_flow(domains: ["crm.agentica.group"], url: "https://evil.example.com/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /not covered by allowed_domains/)
    end

    it "rejects webhooks when no allowlist was declared" do
      expect { define_flow(domains: [], url: "https://crm.agentica.group/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /allowed_domains/)
    end

    it "rejects allowlist entries that are not bare domains" do
      expect { define_flow(domains: ["https://crm.agentica.group"], url: "https://crm.agentica.group/x") }
        .to raise_error(Inquirex::Errors::DefinitionError, /bare domains/)
    end

    it "fails rehydration when the stored JSON was tampered with" do
      definition = define_flow(domains: ["crm.agentica.group"], url: "https://crm.agentica.group/x")
      wire = JSON.parse(definition.to_json)
      wire["actions"][0]["effects"][0]["url"] = "https://exfil.evil.com/x"

      expect { Inquirex::Definition.from_h(wire) }
        .to raise_error(Inquirex::Errors::DefinitionError, /not covered by allowed_domains/)
    end

    it "round-trips allowed_domains through JSON" do
      definition = define_flow(domains: ["crm.agentica.group"], url: "https://crm.agentica.group/x")
      restored = Inquirex::Definition.from_json(definition.to_json)
      expect(restored.allowed_domains).to eq(["crm.agentica.group"])
      expect(restored.actions.first.effects.first).to be_a(described_class)
    end
  end

  describe "serialization round-trip" do
    subject(:restored) { described_class.from_h(effect.to_h) }

    let(:effect) do
      described_class.new(
        url:     "https://crm.agentica.group/leads",
        headers: { "X-Api-Key" => "secret" },
        timeout: 5
      )
    end

    its(:to_h)    { is_expected.to eq(effect.to_h) }
    its(:timeout) { is_expected.to eq(5) }
    its(:headers) { is_expected.to eq("X-Api-Key" => "secret") }
  end
end
