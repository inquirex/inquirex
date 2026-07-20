# frozen_string_literal: true

require "spec_helper"

RSpec.describe Inquirex::CompletionMetadata do
  subject(:metadata) do
    described_class.new(engine: "inquirex-tty", engine_version: "0.5.0", user: "kig")
  end

  it { is_expected.to be_an(OpenStruct) }
  it { is_expected.to respond_to(:user) }
  it { is_expected.not_to respond_to(:hostname) }

  its(:engine)         { is_expected.to eq("inquirex-tty") }
  its(:engine_version) { is_expected.to eq("0.5.0") }
  its(:user)           { is_expected.to eq("kig") }
  its(:hostname)       { is_expected.to be_nil }
  its(:to_h)           { is_expected.to eq(engine: "inquirex-tty", engine_version: "0.5.0", user: "kig") }
  its(:to_json)        { is_expected.to include('"engine":"inquirex-tty"') }

  describe "required members" do
    it "raises without engine" do
      expect { described_class.new(engine_version: "1.0") }.to raise_error(ArgumentError, /engine/)
    end

    it "raises without engine_version" do
      expect { described_class.new(engine: "web") }.to raise_error(ArgumentError, /engine_version/)
    end
  end

  describe "open members" do
    it "creates members on assignment" do
      metadata.hostname = "mbp.local"
      expect(metadata.hostname).to eq("mbp.local")
    end

    it "supports bracket read and write with string or symbol keys" do
      metadata["terminal"] = "iTerm2"
      expect(metadata[:terminal]).to eq("iTerm2")
    end
  end

  describe "nested OpenStruct members" do
    subject(:metadata) do
      described_class.new(
        engine:         "inquirex-tty",
        engine_version: "0.5.0",
        uname:          OpenStruct.new(sysname: "Darwin", machine: "arm64")
      )
    end

    it "keeps dot-access on the nested struct" do
      expect(metadata.uname.machine).to eq("arm64")
    end

    it "deep-converts nested structs in #to_h" do
      expect(metadata.to_h[:uname]).to eq(sysname: "Darwin", machine: "arm64")
    end

    it "serializes to plain nested JSON" do
      expect(JSON.parse(metadata.to_json)).to include(
        "uname" => { "sysname" => "Darwin", "machine" => "arm64" }
      )
    end
  end

  describe ".from_h" do
    it "returns nil for nil or empty input" do
      expect(described_class.from_h(nil)).to be_nil
      expect(described_class.from_h({})).to be_nil
    end

    it "rebuilds from a string-keyed hash (JSON round-trip)" do
      restored = described_class.from_h("engine" => "web", "engine_version" => "2.0", "user" => "kig")
      expect(restored.to_h).to eq(engine: "web", engine_version: "2.0", user: "kig")
    end

    it "re-wraps nested hashes as OpenStructs" do
      restored = described_class.from_h(
        "engine" => "web", "engine_version" => "2.0", "uname" => { "sysname" => "Darwin" }
      )
      expect(restored.uname.sysname).to eq("Darwin")
    end

    it "raises when required members are missing" do
      expect { described_class.from_h("user" => "kig") }.to raise_error(ArgumentError)
    end
  end

  describe "riding on Engine state" do
    subject(:engine) { Inquirex::Engine.new(definition) }

    let(:definition) do
      Inquirex.define id: "meta-test" do
        start :name
        ask :name do
          type :string
          question "What is your name?"
        end
      end
    end

    its(:completion_metadata) { is_expected.to be_nil }

    it "keeps answers_with_metadata identical to answers while unfinished" do
      expect(engine.answers_with_metadata).to eq({})
    end

    it "stamps a minimal core metadata at completion when no hook set one" do
      engine.answer("Alice")
      expect(engine.completion_metadata.to_h)
        .to eq(engine: "inquirex", engine_version: Inquirex::VERSION)
    end

    it "runs after_completion hooks at completion, keeping their metadata" do
      engine.after_completion { |eng| eng.completion_metadata = metadata }
      engine.answer("Alice")
      expect(engine.completion_metadata).to eq(metadata)
    end

    it "invokes after_completion immediately on an already-finished engine" do
      engine.answer("Alice")
      fired = false
      engine.after_completion { fired = true }
      expect(fired).to be(true)
    end

    it "requires a block for after_completion" do
      expect { engine.after_completion }.to raise_error(ArgumentError, /block/)
    end

    it "merges metadata into answers_with_metadata when set" do
      engine.after_completion { |eng| eng.completion_metadata = metadata }
      engine.answer("Alice")
      expect(engine.answers_with_metadata)
        .to eq(name: "Alice", completion_metadata: metadata.to_h)
    end

    it "round-trips through to_state / from_state via JSON" do
      engine.answer("Alice")
      engine.completion_metadata = metadata
      state    = JSON.parse(JSON.generate(engine.to_state))
      restored = Inquirex::Engine.from_state(definition, state)
      expect(restored.completion_metadata).to eq(metadata)
    end

    it "restores a nil completion_metadata from pre-0.6 state hashes" do
      engine.answer("Alice")
      state    = JSON.parse(JSON.generate(engine.to_state.except(:completion_metadata)))
      restored = Inquirex::Engine.from_state(definition, state)
      expect(restored.completion_metadata).to be_nil
    end
  end
end
