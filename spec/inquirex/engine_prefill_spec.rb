# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Engine, "#prefill!" do
  subject(:engine) { described_class.new(definition) }

  let(:definition) do
    Inquirex.define id: "prefill-demo" do
      start :filing_status

      ask :filing_status do
        type :enum
        question "Filing status?"
        options %w[single married]
        skip_if not_empty(:filing_status)
        transition to: :dependents
      end

      ask :dependents do
        type :integer
        question "How many dependents?"
        skip_if not_empty(:dependents)
        transition to: :done
      end

      say :done do
        text "Thanks."
      end
    end
  end

  it "merges values into top-level answers" do
    engine.prefill!(filing_status: "single", dependents: 2)
    expect(engine.answers).to include(filing_status: "single", dependents: 2)
  end

  it "auto-advances past steps whose skip_if becomes satisfied" do
    engine.prefill!(filing_status: "single", dependents: 2)
    expect(engine.current_step_id).to eq(:done)
  end

  it "only skips the currently-asked step when a partial prefill lands" do
    engine.prefill!(filing_status: "single")
    expect(engine.current_step_id).to eq(:dependents)
    expect(engine.answers).to include(filing_status: "single")
  end

  it "ignores nil values" do
    engine.prefill!(filing_status: nil, dependents: 2)
    expect(engine.answers).not_to have_key(:filing_status)
    expect(engine.answers).to include(dependents: 2)
    expect(engine.current_step_id).to eq(:filing_status)
  end

  it "ignores empty strings and empty arrays" do
    engine.prefill!(filing_status: "", dependents: 2)
    expect(engine.answers).not_to have_key(:filing_status)
    expect(engine.current_step_id).to eq(:filing_status)
  end

  it "does not clobber already-answered keys" do
    engine.answer("married")
    engine.prefill!(filing_status: "single", dependents: 3)
    expect(engine.answers[:filing_status]).to eq("married")
    expect(engine.answers[:dependents]).to eq(3)
  end

  it "accepts string keys too" do
    engine.prefill!("filing_status" => "single")
    expect(engine.answers).to include(filing_status: "single")
  end

  it "is a no-op for non-hash input" do
    expect { engine.prefill!(nil) }.not_to raise_error
    expect { engine.prefill!("string") }.not_to raise_error
    expect(engine.current_step_id).to eq(:filing_status)
  end
end
