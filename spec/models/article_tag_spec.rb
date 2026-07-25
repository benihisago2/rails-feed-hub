require "rails_helper"

RSpec.describe ArticleTag do
  subject { build(:article_tag) }

  it "has a valid factory" do
    expect(build(:article_tag)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:article) }
    it { is_expected.to belong_to(:tag) }
  end

  describe "validations" do
    it "does not allow the same tag to be attached to an article twice" do
      existing = create(:article_tag)
      duplicate = build(:article_tag, article: existing.article, tag: existing.tag)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:tag_id]).to be_present
    end

    it "allows the same tag on a different article" do
      existing = create(:article_tag)

      expect(build(:article_tag, article: create(:article), tag: existing.tag)).to be_valid
    end
  end

  describe "database constraints" do
    it "rejects a duplicate (article_id, tag_id) pair even when validations are skipped" do
      existing = create(:article_tag)
      duplicate = build(:article_tag, article: existing.article, tag: existing.tag)

      # Last database statement in the example: the violation aborts the
      # transaction that wraps it.
      expect { duplicate.save(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
