# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Engine, "#text" do
  subject(:engine) { described_class.new(definition) }

  # A help-style flow: mostly telling the user things, with one question that
  # steers which explanation they get. The answers hash is nearly empty, so the
  # transcript is the only record of what the session actually contained.
  let(:definition) do
    Inquirex.define id: "depreciation-help" do
      accumulator :transcript, type: :text
      accumulator :price, type: :currency

      start :intro

      say :intro do
        text "Depreciation spreads an asset's cost over its useful life."
        transition to: :asset_kind
      end

      ask :asset_kind do
        type :enum
        question "What kind of asset?"
        options vehicle: "A vehicle", building: "A building"
        accumulate :price, lookup: { "vehicle" => 100, "building" => 250 }
        transition to: :vehicle_rules, if_rule: equals(:asset_kind, "vehicle")
        transition to: :building_rules
      end

      say :vehicle_rules do
        text "Vehicles use a five-year recovery period."
        transition to: :outro
      end

      say :building_rules do
        text "Buildings use a 27.5-year recovery period."
        transition to: :outro
      end

      say :outro do
        text "That is the short version."
      end
    end
  end

  describe "declaration" do
    it "starts empty rather than at zero" do
      expect(engine.text(:transcript)).to eq("")
    end

    it "leaves numeric accumulators alone" do
      expect(engine.total(:price)).to eq(0)
    end
  end

  describe "capture" do
    before do
      engine.advance            # intro
      engine.answer("vehicle")  # asset_kind
      engine.advance            # vehicle_rules
      engine.advance            # outro
    end

    it "records every display step and every exchange, in order" do
      expect(engine.text(:transcript)).to eq(<<~NARRATIVE.strip)
        Depreciation spreads an asset's cost over its useful life.

        Q: What kind of asset?
        A: A vehicle

        Vehicles use a five-year recovery period.

        That is the short version.
      NARRATIVE
    end

    it "omits the branch the user never saw" do
      expect(engine.text(:transcript)).not_to include("27.5-year")
    end

    it "keeps contributing to numeric accumulators as before" do
      expect(engine.total(:price)).to eq(100)
    end

    it "exposes every text accumulator through #texts" do
      expect(engine.texts.keys).to eq([:transcript])
      expect(engine.texts[:transcript]).to include("five-year")
    end
  end

  describe "steps the engine elides on its own" do
    # `skip_if` removes a step before it is ever rendered. A narrative that
    # claims to record the session must not contain it.
    let(:definition) do
      Inquirex.define id: "elision" do
        accumulator :transcript, type: :text
        start :seed

        ask :seed do
          type :string
          question "Who are you?"
          transition to: :never_shown
        end

        say :never_shown do
          text "YOU SHOULD NOT SEE THIS."
          skip_if not_empty(:seed)
          transition to: :shown
        end

        say :shown do
          text "The end."
        end
      end
    end

    it "excludes a step removed by skip_if" do
      engine.answer("Alan Turing")
      expect(engine.current_step_id).to eq(:shown)
      expect(engine.text(:transcript)).not_to include("YOU SHOULD NOT SEE")
    end

    it "excludes a question auto-skipped because a prefill already answered it" do
      engine.prefill!(seed: "Alan Turing")
      expect(engine.text(:transcript)).to eq("")
    end
  end

  describe "optional questions the user declines" do
    let(:definition) do
      Inquirex.define id: "declined" do
        accumulator :transcript, type: :text
        start :nickname

        ask :nickname do
          type :string
          question "Any nickname?"
          required false
          transition to: :done
        end

        say(:done) { text "Done." }
      end
    end

    it "records the question as skipped rather than dropping it" do
      engine.skip
      expect(engine.text(:transcript)).to start_with("Q: Any nickname?\nA: (skipped)")
    end
  end

  describe "flows with no text accumulator" do
    let(:definition) do
      Inquirex.define id: "plain" do
        start :only
        say(:only) { text "Nothing accumulates here." }
      end
    end

    it "captures nothing and leaves totals untouched" do
      engine.advance
      expect(engine.texts).to be_empty
      expect(engine.totals).to be_empty
    end
  end

  describe "state round-trip" do
    it "survives to_state and from_state" do
      engine.advance
      engine.answer("building")
      restored = described_class.from_state(definition, engine.to_state)
      expect(restored.text(:transcript)).to eq(engine.text(:transcript))
      expect(restored.text(:transcript)).to include("A: A building")
    end
  end
end
