# frozen_string_literal: true

RSpec.describe Inquirex::WidgetRegistry do
  describe ".default_for" do
    {
      string:     { desktop: :text_input,     mobile: :text_input,     tty: :text_input },
      text:       { desktop: :textarea,       mobile: :textarea,       tty: :multiline },
      integer:    { desktop: :number_input,   mobile: :number_input,   tty: :number_input },
      decimal:    { desktop: :number_input,   mobile: :number_input,   tty: :number_input },
      currency:   { desktop: :currency_input, mobile: :currency_input, tty: :number_input },
      boolean:    { desktop: :toggle,         mobile: :yes_no_buttons, tty: :yes_no },
      enum:       { desktop: :radio_group,    mobile: :dropdown,       tty: :select },
      multi_enum: { desktop: :checkbox_group, mobile: :checkbox_group, tty: :multi_select },
      date:       { desktop: :date_picker,    mobile: :date_picker,    tty: :text_input },
      email:      { desktop: :email_input,    mobile: :email_input,    tty: :text_input },
      phone:      { desktop: :phone_input,    mobile: :phone_input,    tty: :text_input }
    }.each do |type, contexts|
      contexts.each do |context, expected_widget|
        it "maps #{type}/#{context} to #{expected_widget}" do
          expect(described_class.default_for(type, context:)).to eq(expected_widget)
        end
      end
    end

    it "returns nil for unknown type" do
      expect(described_class.default_for(:unknown)).to be_nil
    end

    it "returns nil for nil type" do
      expect(described_class.default_for(nil)).to be_nil
    end
  end

  describe ".default_hint_for" do
    it "returns a WidgetHint for known types" do
      hint = described_class.default_hint_for(:enum)
      expect(hint).to be_a(Inquirex::WidgetHint)
      expect(hint.type).to eq(:radio_group)
    end

    it "returns mobile variant" do
      hint = described_class.default_hint_for(:enum, context: :mobile)
      expect(hint.type).to eq(:dropdown)
    end

    it "returns tty variant for enum" do
      hint = described_class.default_hint_for(:enum, context: :tty)
      expect(hint.type).to eq(:select)
    end

    it "returns nil for unknown type" do
      expect(described_class.default_hint_for(:unknown)).to be_nil
    end

    it "returns nil for nil type" do
      expect(described_class.default_hint_for(nil)).to be_nil
    end
  end

  describe "WIDGET_TYPES" do
    subject { described_class::WIDGET_TYPES }

    it { is_expected.to include(:radio_group, :dropdown, :checkbox_group, :select, :multi_select) }
    it { is_expected.to be_frozen }
  end
end
