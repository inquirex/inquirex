# frozen_string_literal: true

# Liquid is NOT a dependency of this gem. It is required here so the "the host
# has Liquid loaded" path of Inquirex::Email is exercised against the real
# thing for the whole suite — every template in every spec really parses. The
# opposite path, a host with no Liquid at all, is covered below by stubbing
# .liquid_template_class, which is the seam that exists for exactly that.
require "liquid"

RSpec.describe Inquirex::Email do
  subject(:definition) do
    Inquirex.load_dsl(DslPayloads.accepted.fetch("send_email declarations"))
  end

  let(:email) { definition.emails.first }

  describe "the DSL verb" do
    it "declares one Email per send_email block, in order" do
      expect(definition.emails.map(&:subject))
        .to eq(["Thank you for filling the form", "New lead: {{ answers.name }}"])
    end

    it "stores the templates verbatim, rendering nothing" do
      expect(email).to have_attributes(
        to:      "{{ answers.email }}",
        from:    "Qualified.At",
        subject: "Thank you for filling the form"
      )
      expect(email.body_markdown).to eq(<<~TEXT)
        Dear {{ answers.name }},

        Thank you for filling out the form. Your total is
        ${{ accumulators.price | round: 2 }} minimum.
      TEXT
    end

    it { expect(email).to be_frozen }

    it "leaves from: nil when the flow does not declare one" do
      expect(definition.emails.last.from).to be_nil
    end

    it "requires a block" do
      expect { Inquirex.define { start(:a); ask(:a) { type(:string) }; send_email } }
        .to raise_error(Inquirex::Errors::DefinitionError, /send_email requires a block/)
    end

    it "is refused without a block in safe mode too, before anything evaluates" do
      blockless = "Inquirex.define do\n  start :a\n  send_email\nend\n"

      expect(Inquirex::SafeSource.validate(blockless))
        .to contain_exactly(/`send_email` requires a block/)
    end
  end

  describe "validation" do
    subject(:build) { described_class.new(**attributes) }

    let(:attributes) { { to: "a@b.c", subject: "Hi", body_markdown: "Hello" } }

    it { is_expected.to be_a(described_class) }

    %i[to subject body_markdown].each do |field|
      it "requires #{field}" do
        missing = attributes.merge(field => nil)

        expect { described_class.new(**missing) }
          .to raise_error(Inquirex::Errors::DefinitionError, /send_email requires #{field}/)
      end

      it "rejects a blank #{field}" do
        blank = attributes.merge(field => "  \n")

        expect { described_class.new(**blank) }
          .to raise_error(Inquirex::Errors::DefinitionError, /send_email requires #{field}/)
      end
    end

    it "rejects a non-String template" do
      pathy = attributes.merge(from: { file: "/etc/passwd" })

      expect { described_class.new(**pathy) }
        .to raise_error(Inquirex::Errors::DefinitionError, /from must be a template String/)
    end
  end

  # The gem cannot render Liquid, but when the process happens to have it, an
  # authoring typo should surface where the author can see it rather than in
  # the host's mail job an hour later.
  describe "Liquid syntax checking" do
    context "when the host has Liquid loaded" do
      it "is the case for this suite" do
        expect(described_class.liquid_template_class).to be(Liquid::Template)
      end

      it "accepts a valid template" do
        expect { described_class.new(to: "a@b.c", subject: "Hi", body_markdown: "{{ answers.name }}") }
          .not_to raise_error
      end

      it "rejects an unterminated tag, naming the field" do
        expect { described_class.new(to: "a@b.c", subject: "Hi", body_markdown: "{% if x %}unclosed") }
          .to raise_error(Inquirex::Errors::DefinitionError, /body_markdown is not valid Liquid/)
      end

      it "rejects a malformed expression in a scalar field" do
        expect { described_class.new(to: "{{ answers. }}", subject: "Hi", body_markdown: "ok") }
          .to raise_error(Inquirex::Errors::DefinitionError, /to is not valid Liquid/)
      end
    end

    context "when the host has no Liquid" do
      before { allow(described_class).to receive(:liquid_template_class).and_return(nil) }

      it "stores even a broken template, leaving validation to the host" do
        email = described_class.new(to: "a@b.c", subject: "Hi", body_markdown: "{% if x %}unclosed")

        expect(email.body_markdown).to eq("{% if x %}unclosed")
      end
    end
  end

  describe "serialization" do
    subject(:wire) { JSON.parse(definition.to_json).fetch("emails") }

    it "emits one entry per declaration, in declaration order" do
      expect(wire.first).to eq(
        "to"            => "{{ answers.email }}",
        "from"          => "Qualified.At",
        "subject"       => "Thank you for filling the form",
        "body_markdown" => email.body_markdown
      )
    end

    it "omits from: when it was not declared" do
      expect(wire.last).not_to have_key("from")
    end

    it "omits the key entirely when a flow declares no emails" do
      bare = Inquirex.load_dsl(DslPayloads.accepted.fetch("minimal"))

      expect(bare.to_h).not_to have_key("emails")
      expect(bare.emails).to be_empty
    end

    describe "round-trip" do
      subject(:restored) { Inquirex::Definition.from_json(definition.to_json) }

      it "rehydrates the declarations" do
        expect(restored.emails.map(&:to_h)).to eq(definition.emails.map(&:to_h))
      end

      it "produces identical JSON on the second pass" do
        expect(JSON.parse(restored.to_json)).to eq(JSON.parse(definition.to_json))
      end

      it "accepts symbol keys too" do
        expect(described_class.from_h(to: "a@b.c", subject: "s", body_markdown: "b").to_h)
          .to eq("to" => "a@b.c", "subject" => "s", "body_markdown" => "b")
      end
    end
  end

  describe "#to_action" do
    subject(:action) { email.to_action("answers" => { "name" => "Ada" }, "accumulators" => {}) }

    its(["type"]) { is_expected.to eq("send_email") }
    its(["to"]) { is_expected.to eq("{{ answers.email }}") }
    its(["context"]) { is_expected.to eq("answers" => { "name" => "Ada" }, "accumulators" => {}) }

    it "carries the raw template, not a rendered one" do
      expect(action["body_markdown"]).to include("{{ answers.name }}")
    end
  end
end
