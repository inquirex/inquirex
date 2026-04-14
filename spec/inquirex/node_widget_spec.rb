# frozen_string_literal: true

RSpec.describe "Node widget hints" do
  subject(:node) do
    Inquirex::Node.new(
      id:           :filing_status,
      verb:         :ask,
      type:         :enum,
      question:     "What is your filing status?",
      options:      { single: "Single", married: "Married" },
      transitions:  [],
      widget_hints: hints
    )
  end

  let(:radio_hint)    { Inquirex::WidgetHint.new(type: :radio_group, options: { columns: 2 }) }
  let(:dropdown_hint) { Inquirex::WidgetHint.new(type: :dropdown) }
  let(:select_hint)   { Inquirex::WidgetHint.new(type: :select) }
  let(:hints)         { { desktop: radio_hint, mobile: dropdown_hint, tty: select_hint } }

  its(:widget_hints) { is_expected.to eq(hints) }

  describe "#widget_hint_for" do
    it "returns the desktop hint" do
      expect(node.widget_hint_for(target: :desktop)).to eq(radio_hint)
    end

    it "returns the mobile hint" do
      expect(node.widget_hint_for(target: :mobile)).to eq(dropdown_hint)
    end

    it "returns the tty hint" do
      expect(node.widget_hint_for(target: :tty)).to eq(select_hint)
    end

    it "returns nil for unknown target" do
      expect(node.widget_hint_for(target: :watch)).to be_nil
    end
  end

  describe "#effective_widget_hint_for" do
    it "returns explicit hint when set" do
      expect(node.effective_widget_hint_for(target: :desktop)).to eq(radio_hint)
    end

    it "falls back to registry default when no hint is set" do
      bare = Inquirex::Node.new(id: :n, verb: :ask, type: :integer, question: "?", transitions: [])
      expect(bare.effective_widget_hint_for(target: :desktop).type).to eq(:number_input)
    end

    it "returns nil for display nodes with no type" do
      say = Inquirex::Node.new(id: :note, verb: :say, text: "Hello", transitions: [])
      expect(say.effective_widget_hint_for(target: :desktop)).to be_nil
    end
  end

  describe "#to_h" do
    subject(:hash) { node.to_h }

    it "nests widget hints under 'widget' key" do
      expect(hash["widget"]).to eq({
        "desktop" => { "type" => "radio_group", "columns" => 2 },
        "mobile"  => { "type" => "dropdown" },
        "tty"     => { "type" => "select" }
      })
    end
  end

  describe "without widget hints" do
    subject(:bare) do
      Inquirex::Node.new(id: :note, verb: :say, text: "Hi", transitions: [])
    end

    its(:widget_hints) { is_expected.to be_nil }

    it "does not include widget key in to_h" do
      expect(bare.to_h).not_to have_key("widget")
    end
  end

  describe "from_h round-trip" do
    let(:restored) { Inquirex::Node.from_h(:filing_status, node.to_h) }

    it "restores desktop hint" do
      expect(restored.widget_hint_for(target: :desktop).type).to eq(:radio_group)
      expect(restored.widget_hint_for(target: :desktop).options).to eq({ columns: 2 })
    end

    it "restores mobile hint" do
      expect(restored.widget_hint_for(target: :mobile).type).to eq(:dropdown)
    end

    it "restores tty hint" do
      expect(restored.widget_hint_for(target: :tty).type).to eq(:select)
    end
  end

  describe "DSL widget verb" do
    let(:definition) do
      Inquirex.define do
        start :q

        ask :q do
          type :enum
          question "Pick one."
          options %w[a b c]
          widget target: :desktop, type: :radio_group, columns: 3
          widget target: :tty,     type: :select
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "carries explicit widget hints" do
      step = definition.step(:q)
      expect(step.widget_hint_for(target: :desktop).type).to eq(:radio_group)
      expect(step.widget_hint_for(target: :desktop).options).to eq({ columns: 3 })
    end

    it "fills registry defaults for unspecified targets" do
      step = definition.step(:q)
      expect(step.widget_hint_for(target: :mobile).type).to eq(:dropdown)
    end

    it "preserves explicit tty hint over default" do
      step = definition.step(:q)
      expect(step.widget_hint_for(target: :tty).type).to eq(:select)
    end

    it "display nodes have nil widget_hints" do
      expect(definition.step(:done).widget_hints).to be_nil
    end
  end

  describe "JSON round-trip through Definition" do
    let(:definition) do
      Inquirex.define id: "widget-test" do
        start :filing_status

        ask :filing_status do
          type :enum
          question "Status?"
          options %w[single married]
          widget target: :desktop, type: :radio_group, columns: 2
          widget target: :mobile,  type: :dropdown
          widget target: :tty,     type: :select
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    it "preserves widget hints through JSON" do
      json = JSON.parse(definition.to_json)
      expect(json["steps"]["filing_status"]["widget"]).to eq({
        "desktop" => { "type" => "radio_group", "columns" => 2 },
        "mobile"  => { "type" => "dropdown" },
        "tty"     => { "type" => "select" }
      })
    end

    it "does not include widget key for display nodes" do
      json = JSON.parse(definition.to_json)
      expect(json["steps"]["done"]).not_to have_key("widget")
    end
  end
end
