# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::Headless do
  subject(:headless) { described_class.new(definition, answers:, yes:) }

  let(:yes) { false }
  let(:answers) { {} }
  # The multi-select carries a skip_if keyed on itself. Fed through prefill!,
  # its value would land as a suggestion that never satisfies that rule, and
  # a run with no TTY would stop on the question forever.
  let(:definition) do
    Inquirex.define id: "headless-demo" do
      start :welcome

      say :welcome do
        text "Welcome."
        transition to: :income_types
      end

      ask :income_types do
        type :multi_enum
        question "Income types?"
        options w2: "W-2", rental: "Rental"
        skip_if not_empty(:income_types)
        transition to: :rental_count, if_rule: contains(:income_types, "rental")
        transition to: :name
      end

      ask :rental_count do
        type :integer
        question "How many rentals?"
        default 1
        transition to: :name
      end

      ask :name do
        type :string
        question "Name?"
        default { |collected| collected[:income_types]&.include?("rental") ? "Landlord" : "Ada Example" }
        transition to: :newsletter
      end

      ask :newsletter do
        type :boolean
        question "Newsletter?"
        required false
        transition to: :done
      end

      say :done do
        text "Thanks."
      end
    end
  end

  # Not memoized: a second #call on a finished run returns the same results.
  def results = headless.call

  # Anything that reads standard input fails the example.
  around do |example|
    original = $stdin
    $stdin = StringIO.new.tap(&:close)
    example.run
  ensure
    $stdin = original
  end

  describe "with every answer given" do
    let(:answers) { { income_types: %w[w2 rental], rental_count: 2, name: "Ada Example", newsletter: true } }

    it "answers the multi-select whose skip_if keys on itself" do
      expect(results[:answers]).to include(income_types: %w[w2 rental], rental_count: 2)
    end

    it "returns every answer" do
      expect(results[:answers].except(:completion_metadata)).to eq(answers)
    end

    it "advances display steps silently and reports the path taken" do
      expect(results[:path_taken]).to eq(%i[welcome income_types rental_count name newsletter done])
      expect(results[:steps_completed]).to eq(6)
    end

    it "finishes the engine" do
      headless.call
      expect(headless.engine).to be_finished
    end
  end

  describe "with string keys, as JSON and YAML files produce them" do
    let(:answers) { { "income_types" => %w[w2], "name" => "Ada Example", "newsletter" => false } }

    it "reads them as step ids" do
      expect(results[:answers].except(:completion_metadata))
        .to eq(income_types: %w[w2], name: "Ada Example", newsletter: false)
    end
  end

  describe "an optional step left out" do
    let(:answers) { { income_types: %w[w2], name: "Ada Example" } }

    it "is skipped, and reported as skipped" do
      expect(results[:answers]).not_to have_key(:newsletter)
      expect(results[:answers][:skipped]).to eq(%i[newsletter])
    end
  end

  describe "a required step left out, without yes" do
    let(:answers) { { income_types: %w[rental] } }

    it "raises MissingAnswer naming the step, even when the step has a default" do
      expect { headless.call }.to raise_error(described_class::MissingAnswer, /rental_count/) do |error|
        expect(error.step_id).to eq(:rental_count)
      end
    end

    it "is an Inquirex error, so a caller's existing rescue catches it" do
      expect { headless.call }.to raise_error(Inquirex::Errors::Error)
    end
  end

  describe "with yes: true" do
    let(:yes) { true }
    let(:answers) { { income_types: %w[rental] } }

    it "takes each missing step's default, calling a Proc default with the answers so far" do
      expect(results[:answers]).to include(rental_count: 1, name: "Landlord")
    end

    it "skips an optional step with no default" do
      expect(results[:answers][:skipped]).to eq(%i[newsletter])
    end

    it "still prefers a given answer to the default" do
      answers[:name] = "Ada Example"
      expect(results[:answers][:name]).to eq("Ada Example")
    end

    context "when a required step has no default and no answer" do
      let(:answers) { {} }

      it "raises MissingAnswer naming the step" do
        expect { headless.call }.to raise_error(described_class::MissingAnswer) do |error|
          expect(error.step_id).to eq(:income_types)
          expect(error.message).to include("income_types")
        end
      end
    end
  end

  describe "an LLM step" do
    let(:adapter) { instance_spy(Proc) }

    let(:definition) do
      Inquirex::Definition.new(
        start_step_id: :profile,
        nodes:         {
          profile: llm_node(default: yes ? { "summary" => "none" } : -> { adapter.call }),
          name:    Inquirex::Node.new(id: :name, verb: :ask, type: :string, question: "Name?", default: "Ada Example")
        }
      )
    end

    # Stands in for Inquirex::LLM::Node, which core cannot load: a collecting
    # node that answers llm_verb?.
    def llm_node(default:)
      Class.new(Inquirex::Node) do
        def collecting? = true
        def display? = false
        def llm_verb? = true
      end.new(id: :profile, verb: :extract, default:, transitions: [Inquirex::Transition.new(target: :name)])
    end

    context "with yes: true" do
      let(:yes) { true }

      it "takes the step's default and never calls the adapter" do
        expect(results[:answers].except(:completion_metadata))
          .to eq(profile: { "summary" => "none" }, name: "Ada Example")
        expect(adapter).not_to have_received(:call)
      end
    end

    context "with an answer given" do
      let(:answers) { { profile: { "summary" => "given" }, name: "Ada Example" } }

      it "uses it, and never calls the adapter or resolves the default" do
        expect(results[:answers][:profile]).to eq("summary" => "given")
        expect(adapter).not_to have_received(:call)
      end
    end

    context "without an answer and without yes" do
      it "raises MissingAnswer without resolving the default or calling the adapter" do
        expect { headless.call }.to raise_error(described_class::MissingAnswer) do |error|
          expect(error.step_id).to eq(:profile)
        end
        expect(adapter).not_to have_received(:call)
      end
    end

    context "with yes: true and no default" do
      let(:yes) { true }
      let(:definition) do
        Inquirex::Definition.new(
          start_step_id: :profile,
          nodes:         {
            profile: llm_node(default: nil),
            name:    Inquirex::Node.new(id: :name, verb: :ask, type: :string, question: "Name?", default: "Ada Example")
          }
        )
      end

      it "records nil for the step instead of stopping" do
        expect(results[:answers]).to include(profile: nil)
      end
    end
  end

  describe "after_completion hooks registered on #engine" do
    let(:answers) { { income_types: %w[w2], name: "Ada Example" } }

    it "run, so a caller can attach its own completion metadata" do
      headless.engine.after_completion do |engine|
        engine.completion_metadata = Inquirex::CompletionMetadata.new(engine: "test", engine_version: "0")
      end
      expect(results[:answers][:completion_metadata]).to include(engine: "test")
    end
  end
end
