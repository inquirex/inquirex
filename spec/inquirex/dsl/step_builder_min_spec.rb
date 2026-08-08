# frozen_string_literal: true

require "rspec/its"

# `min`, `max` and `step_size` bound a numeric step.
#
# The wire fields exist so a renderer can *present* the bound — an HTML number
# input gets stepper arrows and an `:out-of-range` state from them. They are not
# self-enforcing: a visitor can type past a max, and an LLM extraction has no
# notion of one at all. `Node#clamp` is what makes the bound hold, so it is
# pinned here alongside the serialization.
#
# Described as `#min` because that is the entry point RSpec/DescribeMethod wants
# named; `#max`, `#step_size` and the `Node#clamp` they feed are covered here
# too — they are one feature, not three files.
RSpec.describe Inquirex::DSL::StepBuilder, "#min" do
  # Builds a one-step flow, applying +body+ to the step.
  #
  # @param body [Proc] evaluated against the StepBuilder
  # @param type [Symbol] the step's data type
  # @return [Inquirex::Definition]
  def flow(body, type: :integer)
    Inquirex.define id: "bounds-demo" do
      start :employees
      ask :employees do
        type type
        question "How many employees?"
        instance_eval(&body)
      end
    end
  end

  describe "a fully bounded step" do
    subject(:step) { flow(proc { min 1; max 10 }).step(:employees) }

    it { is_expected.to be_bounded }
    its(:min) { is_expected.to eq(1) }
    its(:max) { is_expected.to eq(10) }
    its(:to_h) { is_expected.to include("min" => 1, "max" => 10) }
  end

  describe "a step with no bounds at all" do
    subject(:step) { flow(proc { default 0 }).step(:employees) }

    it { is_expected.not_to be_bounded }
    its(:min) { is_expected.to be_nil }
    its(:to_h) { is_expected.not_to have_key("min") }
    its(:to_h) { is_expected.not_to have_key("max") }
    its(:to_h) { is_expected.not_to have_key("step_size") }
  end

  describe "a half-open bound" do
    subject(:step) { flow(proc { min 0 }).step(:employees) }

    it { is_expected.to be_bounded }
    its(:max) { is_expected.to be_nil }
    its(:to_h) { is_expected.not_to have_key("max") }
  end

  describe "step_size" do
    subject(:step) { flow(proc { step_size 5 }).step(:employees) }

    its(:step_size) { is_expected.to eq(5) }
    its(:to_h) { is_expected.to include("step_size" => 5) }
  end

  describe "#clamp" do
    subject(:step) { flow(proc { min 1; max 10 }).step(:employees) }

    it { expect(step.clamp(900)).to eq(10) }
    it { expect(step.clamp(-40)).to eq(1) }
    it { expect(step.clamp(7)).to eq(7) }
    it { expect(step.clamp(1)).to eq(1) }
    it { expect(step.clamp(10)).to eq(10) }

    it "leaves a non-numeric answer alone rather than inventing a number" do
      expect(step.clamp("not a number")).to eq("not a number")
      expect(step.clamp(nil)).to be_nil
    end

    it "clamps only against the bound that exists" do
      floored = flow(proc { min 0 }).step(:employees)
      expect(floored.clamp(-5)).to eq(0)
      expect(floored.clamp(99_999)).to eq(99_999)
    end

    it "passes everything through on an unbounded step" do
      unbounded = flow(proc { default 0 }).step(:employees)
      expect(unbounded.clamp(-9_999)).to eq(-9_999)
    end
  end

  describe "decimal and currency bounds" do
    %i[decimal currency].each do |type|
      it "accepts a fractional bound on #{type}" do
        step = flow(proc { min 0.5; max 99.99 }, type:).step(:employees)
        expect(step.clamp(150.0)).to eq(99.99)
        expect(step.to_h).to include("min" => 0.5, "max" => 99.99)
      end
    end
  end

  describe "definition errors" do
    it "refuses a min above its max" do
      expect { flow(proc { min 10; max 1 }) }
        .to raise_error(Inquirex::Errors::DefinitionError, /min \(10\) is greater than max \(1\)/)
    end

    it "refuses a bound on a non-numeric type, rather than ignoring it" do
      expect { flow(proc { min 1 }, type: :string) }
        .to raise_error(Inquirex::Errors::DefinitionError, /only apply to/)
    end

    it "refuses a non-numeric bound" do
      expect { flow(proc { min "ten" }) }
        .to raise_error(Inquirex::Errors::DefinitionError, /must be a number/)
    end
  end

  # The path qualified.at actually takes: DSL *text* from a customer, validated
  # against the default-deny allowlist before it is ever evaluated. A keyword
  # the gem implements but never registers is rejected here — which is exactly
  # how `required false` shipped unusable in 0.7.0.
  describe "loading bounded DSL from untrusted source text" do
    subject(:definition) { Inquirex.load_dsl(source) }

    let(:source) { <<~DSL }
      Inquirex.define id: "bounds-source" do
        start :employees
        ask :employees do
          type :integer
          question "How many employees?"
          min 1
          max 10
          step_size 2
          transition to: :employees
        end
      end
    DSL

    it "is accepted by the allowlist rather than refused" do
      expect { definition }.not_to raise_error
    end

    it "carries the bounds through to the built step" do
      step = definition.step(:employees)
      expect(step.min).to eq(1)
      expect(step.max).to eq(10)
      expect(step.step_size).to eq(2)
    end
  end

  describe "round-tripping through the wire format" do
    let(:original) { flow(proc { min 1; max 10; step_size 2 }) }
    let(:restored) { Inquirex::Definition.from_h(original.to_h) }

    it "carries every bound back out again" do
      step = restored.step(:employees)
      expect(step.min).to eq(1)
      expect(step.max).to eq(10)
      expect(step.step_size).to eq(2)
    end

    it "serializes identically after a round trip" do
      expect(restored.to_h).to eq(original.to_h)
    end
  end
end
