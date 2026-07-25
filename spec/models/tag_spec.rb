require "rails_helper"

RSpec.describe Tag do
  subject { build(:tag) }

  it "has a valid factory" do
    expect(build(:tag)).to be_valid
  end

  describe "associations" do
    it { is_expected.to have_many(:article_tags).dependent(:destroy) }
    it { is_expected.to have_many(:articles).through(:article_tags) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    # case_insensitive, because normalize_name downcases before the uniqueness
    # check runs -- "Ruby" and "ruby" are the same tag.
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
  end

  describe "name normalisation" do
    it "strips surrounding whitespace and downcases" do
      tag = build(:tag, name: "  Ruby ON Rails  ")
      tag.validate

      expect(tag.name).to eq("ruby on rails")
    end

    it "persists the normalised value" do
      expect(create(:tag, name: " Rails ").reload.name).to eq("rails")
    end

    it "treats a name differing only in case or padding as a duplicate" do
      create(:tag, name: "rails")

      expect(build(:tag, name: " RAILS ")).not_to be_valid
    end

    it "leaves a nil name alone so the presence validation can report it" do
      tag = build(:tag, name: nil)

      expect(tag).not_to be_valid
      expect(tag.errors[:name]).to be_present
    end
  end

  describe "database constraints" do
    it "rejects a second tag with the same name" do
      create(:tag, name: "ruby")
      duplicate = build(:tag, name: "ruby")

      # Last database statement in the example on purpose: the violation aborts
      # the transaction rspec-rails wraps around it.
      expect { duplicate.save(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
