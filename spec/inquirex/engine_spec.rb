# frozen_string_literal: true

RSpec.describe Inquirex::Engine do
  subject(:engine) { described_class.new(definition) }

  let(:definition) do
    Inquirex.define do
      start :name

      ask :name do
        type :string
        question "What is your name?"
        transition to: :age
      end

      ask :age do
        type :integer
        question "How old are you?"
        transition to: :adult_notice, if_rule: greater_than(:age, 17)
        transition to: :minor_notice
      end

      say :adult_notice do
        text "Welcome, adult!"
        transition to: :done
      end

      say :minor_notice do
        text "You are a minor."
        transition to: :done
      end

      say :done do
        text "All done."
      end
    end
  end

  its(:current_step_id) { is_expected.to eq(:name) }
  it { is_expected.not_to be_finished }

  describe "#current_step" do
    it { expect(engine.current_step).to be_a(Inquirex::Node) }
    its(:current_step) { is_expected.to have_attributes(id: :name, verb: :ask) }
  end

  describe "#answer" do
    it "advances to next step after answering" do
      engine.answer("Alice")
      expect(engine.current_step_id).to eq(:age)
    end

    it "stores the answer" do
      engine.answer("Alice")
      expect(engine.answers[:name]).to eq("Alice")
    end

    it "follows conditional transitions" do
      engine.answer("Alice")
      engine.answer(25)
      expect(engine.current_step_id).to eq(:adult_notice)
    end

    it "follows fallback transition for minor" do
      engine.answer("Bob")
      engine.answer(16)
      expect(engine.current_step_id).to eq(:minor_notice)
    end

    it "raises AlreadyFinishedError when flow is done" do
      engine.answer("Alice")
      engine.answer(25)
      engine.advance  # adult_notice
      engine.advance  # done
      expect { engine.answer("extra") }.to raise_error(Inquirex::Errors::AlreadyFinishedError)
    end

    it "raises NonCollectingStepError when called on a say step" do
      engine.answer("Alice")
      engine.answer(25) # goes to :adult_notice (say step)
      expect { engine.answer("value") }.to raise_error(Inquirex::Errors::NonCollectingStepError)
    end
  end

  describe "#advance" do
    it "advances past a say step" do
      engine.answer("Alice")
      engine.answer(25)
      expect(engine.current_step_id).to eq(:adult_notice)
      engine.advance
      expect(engine.current_step_id).to eq(:done)
    end

    it "marks finished when advancing past last step" do
      engine.answer("Alice")
      engine.answer(25)
      engine.advance
      engine.advance
      expect(engine).to be_finished
    end

    it "raises AlreadyFinishedError when already finished" do
      engine.answer("Alice")
      engine.answer(25)
      engine.advance
      engine.advance
      expect { engine.advance }.to raise_error(Inquirex::Errors::AlreadyFinishedError)
    end
  end

  describe "#history" do
    it "records visited steps" do
      engine.answer("Alice")
      engine.answer(25)
      engine.advance
      expect(engine.history).to eq(%i[name age adult_notice done])
    end
  end

  describe "#to_state / .from_state" do
    it "round-trips state" do
      engine.answer("Alice")
      state = engine.to_state
      restored = described_class.from_state(definition, state)
      expect(restored.current_step_id).to eq(:age)
      expect(restored.answers[:name]).to eq("Alice")
    end

    it "handles JSON-round-tripped state (string keys)" do
      engine.answer("Alice")
      state_json = engine.to_state.transform_keys(&:to_s)
      restored = described_class.from_state(definition, state_json)
      expect(restored.current_step_id).to eq(:age)
    end
  end
end
