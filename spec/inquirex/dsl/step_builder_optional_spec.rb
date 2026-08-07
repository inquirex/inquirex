# frozen_string_literal: true

require "rspec/its"

# `optional` is the inverse spelling of `required`. Since steps are required by
# default, `required true` is a no-op and the keyword only ever appeared as
# `required false`; these examples pin the sugar down to the same single wire
# field so a definition round-trips identically however it was authored.
RSpec.describe Inquirex::DSL::StepBuilder, "#optional" do
  # Builds a one-step flow, applying +body+ to the step.
  #
  # @param body [Proc] evaluated against the StepBuilder
  # @return [Inquirex::Definition]
  def flow(body)
    Inquirex.define id: "optional-demo" do
      start :dependents
      ask :dependents do
        type :integer
        question "How many dependents?"
        instance_eval(&body)
      end
    end
  end

  describe "the optional spelling" do
    subject(:step) { flow(proc { optional }).step(:dependents) }

    it { is_expected.not_to be_required }
    its(:to_h) { is_expected.to include("required" => false) }
  end

  describe "optional true" do
    subject(:step) { flow(proc { optional true }).step(:dependents) }

    it { is_expected.not_to be_required }
  end

  describe "optional false" do
    subject(:step) { flow(proc { optional false }).step(:dependents) }

    it { is_expected.to be_required }
    its(:to_h) { is_expected.not_to have_key("required") }
  end

  describe "the default, with neither keyword" do
    subject(:step) { flow(proc { default 0 }).step(:dependents) }

    it { is_expected.to be_required }
    its(:to_h) { is_expected.not_to have_key("required") }
  end

  describe "wire-format parity with required false" do
    let(:via_optional) { flow(proc { optional }).to_h }
    let(:via_required) { flow(proc { required false }).to_h }

    it "serializes to the identical hash, so no consumer learns a second key" do
      expect(via_optional).to eq(via_required)
    end

    it "round-trips back to a skippable step" do
      rehydrated = Inquirex::Definition.from_h(JSON.parse(flow(proc { optional }).to_json))
      expect(rehydrated.step(:dependents)).not_to be_required
    end
  end

  describe "contradictory declarations" do
    let(:required_then_optional) do
      proc do
        required true
        optional true
      end
    end

    let(:optional_then_required) do
      proc do
        optional
        required
      end
    end

    it "raises rather than letting the last call win" do
      expect { flow(required_then_optional) }
        .to raise_error(Inquirex::Errors::DefinitionError, /both required and optional/)
    end

    it "raises in the other order too" do
      expect { flow(optional_then_required) }
        .to raise_error(Inquirex::Errors::DefinitionError, /both required and optional/)
    end
  end

  describe "agreeing declarations" do
    subject(:step) { flow(agreeing).step(:dependents) }

    let(:agreeing) do
      proc do
        required false
        optional true
      end
    end

    it "tolerates the redundant pair, since they say the same thing" do
      expect(step).not_to be_required
    end
  end

  describe "stored DSL" do
    let(:source) do
      <<~DSL
        Inquirex.define id: "stored" do
          start :dependents
          ask :dependents do
            type :integer
            question "How many dependents?"
            optional
          end
        end
      DSL
    end

    it "passes SafeSource, so a host's default-deny validator does not reject it" do
      expect(Inquirex::SafeSource.validate(source)).to be_empty
    end

    it "loads to a skippable step" do
      expect(Inquirex.load_dsl(source).step(:dependents)).not_to be_required
    end
  end
end
