# frozen_string_literal: true

# Serialization and DSL behavior of send_email declarations on Definition.
RSpec.describe Inquirex::Definition do
  subject(:definition) do
    Inquirex.define id: "emails-wire", version: "2.0.0" do
      start :email
      ask(:email) { type(:email); question("Email?") }

      # Block-builder form, gated on the answer being present. The subject
      # call here is the SendEmailBuilder setter, not RSpec's subject.
      # rubocop:disable RSpec/VariableDefinition, RSpec/VariableName
      send_email if: not_empty(:email) do
        to      "{{email}}"
        from    "forms@agentica.group"
        subject "Thanks!"
        markdown_text "Hi {{email}}\n\n{{answers_summary}}"
      end
      # rubocop:enable RSpec/VariableDefinition, RSpec/VariableName

      # Inline keyword form, ungated.
      send_email to: "admin@x.co", subject: "Lead", html: "{{answers_summary}}"
    end
  end

  let(:wire) { JSON.parse(definition.to_json) }

  describe "to_json" do
    it "serializes send_email declarations in order under send_emails" do
      expect(wire["send_emails"].map { |e| e["to"] }).to eq(["{{email}}", "admin@x.co"])
    end

    it "serializes the gate rule under if" do
      expect(wire.dig("send_emails", 0, "if")).to eq("op" => "not_empty", "field" => "email")
      expect(wire.dig("send_emails", 1)).not_to have_key("if")
    end

    it "carries the markdown body on the wire" do
      expect(wire.dig("send_emails", 0, "markdown_text")).to start_with("Hi {{email}}")
    end

    it "omits the key entirely when no emails are declared" do
      bare = Inquirex.define id: "bare" do
        start :a
        ask(:a) { type(:string); question("?") }
      end
      expect(JSON.parse(bare.to_json)).not_to have_key("send_emails")
    end
  end

  describe "from_json round-trip" do
    subject(:restored) { described_class.from_json(definition.to_json) }

    it "rehydrates emails with their rules" do
      expect(restored.send_emails.size).to eq(2)
      expect(restored.send_emails.first).to be_a(Inquirex::SendEmail)
      expect(restored.send_emails.first.rule).to be_a(Inquirex::Rules::NotEmpty)
    end

    it "produces identical JSON on the second pass" do
      expect(JSON.parse(restored.to_json)).to eq(wire)
    end

    it "gates rehydrated emails via applicable?" do
      answers = { email: "ada@lovelace.io" }
      expect(restored.send_emails.select { |e| e.applicable?(answers) }.size).to eq(2)
      expect(restored.send_emails.select { |e| e.applicable?({}) }.size).to eq(1)
    end
  end

  describe "DSL guards" do
    it "rejects a send_email without a recipient" do
      expect do
        Inquirex.define id: "no-to" do
          start :a
          ask(:a) { type(:string); question("?") }
          # rubocop:disable RSpec/VariableDefinition
          send_email { subject("s"); text("t") }
          # rubocop:enable RSpec/VariableDefinition
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /requires to:/)
    end

    it "rejects unknown send_email fields" do
      expect do
        Inquirex.define id: "opts" do
          start :a
          ask(:a) { type(:string); question("?") }
          send_email to: "a@b.c", subject: "s", text: "t", when: :always
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /send_email: unknown keyword/)
    end

    it "rejects unknown builder words inside the block" do
      expect do
        Inquirex.define id: "verbs" do
          start :a
          ask(:a) { type(:string); question("?") }
          send_email { teleport "the moon" }
        end
      end.to raise_error(NoMethodError, /teleport/)
    end

    it "lets block values override inline keywords" do
      definition = Inquirex.define id: "override" do
        start :a
        ask(:a) { type(:string); question("?") }
        send_email(to: "inline@x.co", subject: "s", text: "t") { to "block@x.co" }
      end
      expect(definition.send_emails.first.to).to eq("block@x.co")
    end

    it "removed the legacy action verb" do
      expect do
        Inquirex.define id: "legacy" do
          start :a
          ask(:a) { type(:string); question("?") }
          action(:receipt) { send_email to: "a@b.c", subject: "s", text: "t" }
        end
      end.to raise_error(NoMethodError, /action/)
    end
  end
end
