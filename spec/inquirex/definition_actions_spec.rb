# frozen_string_literal: true

# Serialization and DSL behavior of post-completion actions on Definition.
RSpec.describe Inquirex::Definition do
  subject(:definition) do
    Inquirex.define id: "actions-wire", version: "2.0.0" do
      start :email
      ask(:email) { type(:email); question("Email?") }

      action :receipt, if: not_empty(:email) do
        send_email to: "{{email}}", subject: "Thanks!", text: "Hi {{email}}"
      end

      action :ruby_only do
        run { |_answers, _outbox| :noop }
      end

      action :mixed do
        send_email to: "admin@x.co", subject: "Lead", html: "{{answers_summary}}"
        run { |_answers, _outbox| :noop }
      end
    end
  end

  let(:wire) { JSON.parse(definition.to_json) }

  describe "to_json" do
    it "serializes actions with their rules" do
      expect(wire["actions"].map { |a| a["id"] }).to eq(%w[receipt mixed])
      expect(wire.dig("actions", 0, "if")).to eq("op" => "not_empty", "field" => "email")
    end

    it "strips run blocks and omits actions left with no effects" do
      expect(wire["actions"].map { |a| a["id"] }).not_to include("ruby_only")
      expect(wire.dig("actions", 1, "effects").size).to eq(1)
    end

    it "serializes effects with their type tag" do
      expect(wire.dig("actions", 0, "effects", 0))
        .to include("type" => "send_email", "to" => "{{email}}")
    end
  end

  describe "from_json round-trip" do
    subject(:restored) { described_class.from_json(definition.to_json) }

    it "rehydrates actions, rules, and effects" do
      expect(restored.actions.map(&:id)).to eq(%i[receipt mixed])
      expect(restored.actions.first.rule).to be_a(Inquirex::Rules::NotEmpty)
      expect(restored.actions.first.effects.first).to be_a(Inquirex::Actions::SendEmail)
    end

    it "produces identical JSON on the second pass" do
      expect(JSON.parse(restored.to_json)).to eq(wire)
    end

    it "raises on unknown effect types" do
      corrupted = wire.dup
      corrupted["actions"][0]["effects"][0]["type"] = "teleport"
      expect { described_class.from_h(corrupted) }
        .to raise_error(Inquirex::Errors::SerializationError, /teleport/)
    end
  end

  describe "DSL guards" do
    it "rejects duplicate action ids" do
      expect do
        Inquirex.define id: "dup" do
          start :a
          ask(:a) { type(:string); question("?") }
          action(:x) { send_email to: "a@b.c", subject: "s", text: "t" }
          action(:x) { send_email to: "a@b.c", subject: "s", text: "t" }
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /Duplicate action id/)
    end

    it "rejects actions with no effects" do
      expect do
        Inquirex.define id: "empty" do
          start :a
          ask(:a) { type(:string); question("?") }
          action(:nothing)
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /declares no effects/)
    end

    it "rejects unknown action options" do
      expect do
        Inquirex.define id: "opts" do
          start :a
          ask(:a) { type(:string); question("?") }
          action(:x, when: :always) { run { :noop } }
        end
      end.to raise_error(Inquirex::Errors::DefinitionError, /Unknown action options/)
    end

    it "rejects unknown effect verbs" do
      expect do
        Inquirex.define id: "verbs" do
          start :a
          ask(:a) { type(:string); question("?") }
          action(:x) { teleport to: "the moon" }
        end
      end.to raise_error(NoMethodError, /teleport/)
    end
  end
end
