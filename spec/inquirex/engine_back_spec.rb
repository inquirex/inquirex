# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Engine, "#back" do
  subject(:engine) { described_class.new(definition) }

  # Every kind of state a step can leave behind: a lookup and a per-selection
  # price, a per-unit price fed by a Proc default, the :text transcript, a
  # user skip, and a prefill! suggestion. A display step sits between the
  # first two questions so `back` has something to step over.
  let(:definition) do
    Inquirex.define id: "back-demo" do
      accumulator :price, type: :currency, default: 0
      accumulator :transcript, type: :text

      start :filing_status

      ask :filing_status do
        type :enum
        question "Filing status?"
        options single: "Single", married: "Married"
        accumulate :price, lookup: { "single" => 100, "married" => 200 }
        transition to: :intro
      end

      say :intro do
        text "Now a few questions about your income."
        transition to: :income_types
      end

      ask :income_types do
        type :multi_enum
        question "Income types?"
        options w2: "W-2", rental: "Rental"
        accumulate :price, per_selection: { "w2" => 10, "rental" => 50 }
        transition to: :dependents
      end

      ask :dependents do
        type :integer
        question "How many dependents?"
        required false
        default { |answers| answers[:filing_status] == "married" ? 2 : 1 }
        price per_unit: 25
        transition to: :done
      end

      say :done do
        text "All done."
      end
    end
  end

  # to_state hands out the engine's live hashes, so a "before" picture has to
  # be a deep copy or it would change along with the engine.
  def snapshot = Marshal.load(Marshal.dump(engine.to_state))

  describe "at the first collecting step" do
    it "returns false" do
      expect(engine.back).to be(false)
    end

    it "changes nothing" do
      before = snapshot
      engine.back
      expect(engine.to_state).to eq(before)
    end

    it { is_expected.not_to be_can_back }

    context "when the flow opens with a display step" do
      let(:definition) do
        Inquirex.define id: "back-opening-say" do
          start :welcome

          say :welcome do
            text "Welcome."
            transition to: :name
          end

          ask :name do
            type :string
            question "Name?"
          end
        end
      end

      before { engine.advance }

      it "does not go back to a step that collects nothing" do
        before = snapshot
        expect(engine.back).to be(false)
        expect(engine.to_state).to eq(before)
      end

      it { is_expected.not_to be_can_back }
    end
  end

  describe "after one answer" do
    it "restores the whole state from before the answer" do
      before = snapshot
      engine.answer("married")
      expect(engine.back).to be(true)
      expect(engine.to_state).to eq(before)
    end

    it "becomes possible once a question is answered" do
      engine.answer("married")
      expect(engine).to be_can_back
    end
  end

  describe "over a display step" do
    before { engine.answer("single") }

    it "steps over the display step back to the question before it" do
      before = snapshot
      engine.advance
      expect(engine.current_step_id).to eq(:income_types)
      engine.back
      expect(engine.current_step_id).to eq(:filing_status)
      expect(engine.answers).not_to have_key(:filing_status)
      expect(engine.total(:price)).to eq(0)
      expect(engine.text(:transcript)).to eq("")
      expect(before[:current_step_id]).to eq(:intro)
    end

    it "lands on the display step's predecessor, not the display step" do
      engine.advance
      engine.back
      expect(engine.current_step).to be_collecting
    end
  end

  describe "an accumulator step" do
    before do
      engine.answer("single")
      engine.advance
    end

    it "takes the step's contribution back out of the total" do
      before = snapshot
      engine.answer(%w[w2 rental])
      expect(engine.total(:price)).to eq(160)
      engine.back
      expect(engine.to_state).to eq(before)
      expect(engine.total(:price)).to eq(100)
    end
  end

  describe "a prefill!-derived suggestion" do
    before do
      engine.prefill!(income_types: ["Rental"])
      engine.answer("single")
      engine.advance
    end

    it "comes back after the answer that consumed it is undone" do
      before = snapshot
      expect(engine.suggestion_for(:income_types)).to eq(["rental"])
      engine.answer(%w[w2])
      expect(engine.suggestion_for(:income_types)).to be_nil
      engine.back
      expect(engine.to_state).to eq(before)
      expect(engine.suggestion_for(:income_types)).to eq(["rental"])
    end
  end

  describe "a skip that recorded a Proc default" do
    before do
      engine.answer("married")
      engine.advance
      engine.answer(%w[w2])
    end

    it "removes the default, the skip and its price" do
      before = snapshot
      engine.skip
      expect(engine.answers[:dependents]).to eq(2)
      expect(engine).to be_skipped(:dependents)
      engine.back
      expect(engine.to_state).to eq(before)
      expect(engine).not_to be_skipped(:dependents)
    end
  end

  describe "from a finished flow" do
    before do
      engine.answer("married")
      engine.advance
      engine.answer(%w[w2])
    end

    it "returns to the last question and clears the completion metadata" do
      before = snapshot
      engine.answer(3)
      engine.advance
      expect(engine).to be_finished
      engine.back
      expect(engine.to_state).to eq(before)
      expect(engine.completion_metadata).to be_nil
    end

    it "keeps after_completion hooks, so finishing again runs them again" do
      calls = []
      engine.after_completion { calls << :done }
      engine.answer(3)
      engine.advance
      engine.back
      engine.answer(4)
      engine.advance
      expect(calls).to eq(%i[done done])
    end
  end

  describe "repeated back" do
    it "walks back one question at a time to the start" do
      start = snapshot
      engine.answer("married")
      engine.advance
      after_first = snapshot
      engine.answer(%w[w2 rental])

      engine.back
      expect(engine.to_state).to eq(after_first)
      engine.back
      expect(engine.to_state).to eq(start)
      expect(engine.back).to be(false)
    end
  end

  describe "a failed answer" do
    subject(:engine) { described_class.new(definition, validator:) }

    let(:validator) do
      Class.new(Inquirex::Validation::Adapter) do
        def validate(_node, value)
          Inquirex::Validation::Result.new(valid: value != "bogus", errors: ["bogus"])
        end
      end.new
    end

    it "leaves nothing to go back to" do
      expect { engine.answer("bogus") }.to raise_error(Inquirex::Errors::ValidationError)
      expect(engine).not_to be_can_back
    end
  end

  describe "#previous_answer" do
    it "is nil for a step never answered" do
      expect(engine.previous_answer(:filing_status)).to be_nil
    end

    it "returns the undone answer, to pre-fill the re-asked question" do
      engine.answer("married")
      engine.back
      expect(engine.previous_answer(:filing_status)).to eq("married")
      expect(engine.previous_answer("filing_status")).to eq("married")
    end

    it "remembers every answer undone by repeated back" do
      engine.answer("married")
      engine.advance
      engine.answer(%w[rental])
      engine.back
      engine.back
      expect(engine.previous_answer(:filing_status)).to eq("married")
      expect(engine.previous_answer(:income_types)).to eq(%w[rental])
    end

    it "prefers the current answer once the step is answered again" do
      engine.answer("married")
      engine.back
      engine.answer("single")
      expect(engine.previous_answer(:filing_status)).to eq("single")
    end
  end

  describe "persistence" do
    it "keeps the snapshot stack out of to_state" do
      engine.answer("married")
      expect(engine.to_state.keys).to contain_exactly(
        :current_step_id, :answers, :history, :totals, :suggestions, :skipped, :completion_metadata
      )
    end

    it "starts a restored engine with nothing to go back to" do
      engine.answer("married")
      restored = described_class.from_state(definition, JSON.parse(engine.to_state.to_json))
      expect(restored).not_to be_can_back
      expect(restored.back).to be(false)
    end
  end
end
