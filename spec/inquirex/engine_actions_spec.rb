# frozen_string_literal: true

# Liquid stands in for the host here — this gem does not depend on it. See the
# note at the top of spec/inquirex/email_spec.rb.
require "liquid"

# What the engine hands a host for rendering: the Liquid context mid-flow, and
# the advisory action list once the flow is done.
RSpec.describe Inquirex::Engine do
  subject(:engine) { described_class.new(definition) }

  # Written as source rather than a Ruby block so that the flow goes through
  # the validating load path — and so RuboCop does not read the DSL's own
  # `subject` setter as RSpec's.
  let(:definition) { Inquirex.load_dsl(source) }

  let(:source) do
    <<~RUBY
      Inquirex.define id: "waitlist" do
        accumulator :price, type: :currency, default: 0
        start :name

        ask :name do
          type :string
          question "What is your name?"
          transition to: :status
        end

        ask :status do
          type :enum
          question "Thanks {{ answers.name }}, which describes you?"
          options individual: "Individual", business: "Business"
          price individual: 200, business: 400
          transition to: :done
        end

        say :done do
          text "Your estimate is ${{ accumulators.price | round: 2 }}."
        end

        send_email do
          to      "{{ answers.name }}@example.com"
          from    "Qualified.At"
          subject "Thank you for filling the form"
          body_markdown "Your total is ${{ accumulators.price | round: 2 }} minimum."
        end
      end
    RUBY
  end

  # Rendering happens at display time, not load time: :status asks about an
  # answer collected at :name.
  describe "#render_context" do
    it "is empty-ish before anything is collected" do
      expect(engine.render_context).to eq("answers" => {}, "accumulators" => { "price" => 0 })
    end

    it "grows as the wizard progresses" do
      engine.answer("Ada")

      expect(engine.render_context).to eq(
        "answers"      => { "name" => "Ada" },
        "accumulators" => { "price" => 0 }
      )
    end

    it "carries accumulator totals once they are contributed to" do
      engine.answer("Ada")
      engine.answer("business")

      expect(engine.render_context.fetch("accumulators")).to eq("price" => 400)
    end

    it "is plain and JSON-serializable: Symbols become Strings, nesting survives" do
      engine.answer("Ada")
      engine.answers[:business] = { type: :llc, partners: [:ada, "bob"] }
      context = engine.render_context

      expect(context.fetch("answers").fetch("business"))
        .to eq("type" => "llc", "partners" => %w[ada bob])
      expect(JSON.parse(JSON.generate(context))).to eq(context)
    end

    it "returns a fresh hash the caller may keep" do
      expect(engine.render_context).not_to be(engine.render_context)
    end
  end

  describe "#on_complete_actions" do
    it { expect(engine.on_complete_actions).to be_empty }

    it "stays empty while the flow is unfinished" do
      engine.answer("Ada")

      expect(engine.on_complete_actions).to be_empty
    end

    context "when the flow is finished" do
      subject(:actions) { engine.on_complete_actions }

      before do
        engine.answer("Ada")
        engine.answer("business")
        engine.advance
      end

      it { expect(engine).to be_finished }
      it { is_expected.to have_attributes(size: 1) }

      it "tags each entry with its type, so new types stay additive" do
        expect(actions.map { |action| action["type"] }).to eq(["send_email"])
      end

      it "carries the raw templates — the gem renders nothing" do
        expect(actions.first).to include(
          "to"            => "{{ answers.name }}@example.com",
          "from"          => "Qualified.At",
          "subject"       => "Thank you for filling the form",
          "body_markdown" => "Your total is ${{ accumulators.price | round: 2 }} minimum."
        )
      end

      it "pairs them with the context, so the entry is self-contained" do
        expect(actions.first.fetch("context")).to eq(
          "answers"      => { "name" => "Ada", "status" => "business" },
          "accumulators" => { "price" => 400 }
        )
      end

      it "survives a round-trip through a job queue unchanged" do
        expect(JSON.parse(JSON.generate(actions))).to eq(actions)
      end

      # The gem hands over data; whether any of it happens is the host's call.
      it "builds no Mail::Message and delivers nothing" do
        expect(actions.first.values).to all(be_a(String).or(be_a(Hash)))
        expect(engine.answers.keys).to contain_exactly(:name, :status)
      end

      # The realistic host path: the wizard session lives in a cache, and the
      # actions are read off an engine rebuilt from it.
      it "is identical on an engine restored from persisted state" do
        restored = described_class.from_state(definition, JSON.parse(JSON.generate(engine.to_state)))

        expect(restored.on_complete_actions).to eq(actions)
      end

      it "is what a host would render with" do
        rendered = Liquid::Template.parse(actions.first.fetch("body_markdown"))
                                   .render(actions.first.fetch("context"))

        expect(rendered).to eq("Your total is $400 minimum.")
      end
    end

    it "is empty for a flow that declares no emails" do
      finished = described_class.new(Inquirex.load_dsl(DslPayloads.accepted.fetch("minimal")))
      finished.advance

      expect(finished.on_complete_actions).to be_empty
    end
  end
end
