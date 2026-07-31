# frozen_string_literal: true

RSpec.describe Inquirex::Actions::Runner do
  subject(:answers) { Inquirex::Actions.run(definition, name: "Ada", email: "ada@lovelace.io") }

  let(:definition) do
    Inquirex.define id: "runner-spec" do
      start :name
      ask(:name)  { type(:string); question("Name?"); transition(to: :email) }
      ask(:email) { type(:email); question("Email?") }

      action :receipt, if: not_empty(:email) do
        send_email to: "{{email}}", subject: "Thanks {{name}}!", text: "Hi {{name}}"
      end

      action :gated, if: equals(:name, "nobody") do
        send_email to: "admin@x.co", subject: "never", text: "never"
      end
    end
  end

  describe "the returned answers" do
    it { is_expected.to be_a(Inquirex::Answers) }
    its(:name) { is_expected.to eq("Ada") }

    it "does not leak the outbox into serialized data" do
      expect(answers.to_json).not_to include("outbox")
      expect(answers.to_h.keys).to contain_exactly(:name, :email)
    end
  end

  describe "the outbox" do
    subject(:outbox) { answers.outbox }

    its(:size) { is_expected.to eq(1) }
    its(:failures) { is_expected.to be_empty }

    it "builds the gated email only when its rule passes" do
      expect(outbox.messages.first.to).to eq(["ada@lovelace.io"])
    end

    it "records ok and skipped results in declaration order" do
      expect(outbox.results.map { |r| [r.action_id, r.status] }).to eq(
        [[:receipt, :ok], [:gated, :skipped]]
      )
    end
  end

  # Built without the DSL: with `run` gone there is no DSL word that can raise
  # on purpose, and a host-registered effect (the extension point the registry
  # exists for) is exactly what this behavior protects.
  describe "failure isolation" do
    subject(:outbox) { Inquirex::Actions.run(definition, name: "Ada").outbox }

    let(:failing_effect) do
      Class.new(Inquirex::Actions::Base) do
        def call(_answers, _outbox) = raise("kaput")
      end.new
    end

    let(:definition) do
      Inquirex::Definition.new(
        start_step_id: :name,
        nodes:         { name: Inquirex::Node.new(id: :name, verb: :ask, type: :string, question: "Name?") },
        actions:       [
          Inquirex::Actions::Action.new(id: :boom, effects: [failing_effect]),
          Inquirex::Actions::Action.new(
            id:      :after,
            effects: [Inquirex::Actions::SendEmail.new(to: "a@b.c", subject: "still runs", text: "t")]
          )
        ]
      )
    end

    it "records the failure and keeps going" do
      expect(outbox.failures.map(&:action_id)).to eq([:boom])
      expect(outbox.failures.first.error).to be_a(RuntimeError)
      expect(outbox.messages.first.subject).to eq("still runs")
    end
  end

  describe "with an Answers instance as input" do
    subject(:result) { Inquirex::Actions.run(definition, input) }

    let(:input) { Inquirex::Answers.new(name: "Ada", email: "a@b.c") }

    it "returns the same instance with its outbox populated" do
      expect(result).to be(input)
      expect(result.outbox.size).to eq(1)
    end
  end
end
