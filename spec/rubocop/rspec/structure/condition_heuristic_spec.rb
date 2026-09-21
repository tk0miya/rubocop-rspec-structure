# frozen_string_literal: true

RSpec.describe RuboCop::RSpec::Structure::ConditionHeuristic do
  subject(:heuristic) { described_class.new(keywords: %w[の場合 場合 のとき 際 when if]) }

  context "with Japanese keywords" do
    context "when the description ends in の場合" do
      it "matches" do
        expect(heuristic).to be_condition("管理者権限を持っている場合は削除できる")
      end
    end

    context "when the description ends in のとき" do
      it "matches" do
        expect(heuristic).to be_condition("ユーザーが未ログインのとき、ログイン画面を表示する")
      end
    end

    context "when the description contains の際" do
      it "matches" do
        expect(heuristic).to be_condition("在庫がない際は購入ボタンが非表示になる")
      end
    end

    context "when the description has no condition" do
      it "does not match" do
        expect(heuristic).not_to be_condition("削除できる")
      end
    end

    context "when the kanji keyword is the tail of another word" do
      it "does not match" do
        expect(heuristic).not_to be_condition("実際に削除されること")
        expect(heuristic).not_to be_condition("国際化対応がされていること")
      end
    end
  end

  context "with English keywords" do
    context "when the description contains when as a whole word" do
      it "matches" do
        expect(heuristic).to be_condition("shows an error when the input is invalid")
      end
    end

    context "when the description contains if as a whole word" do
      it "matches" do
        expect(heuristic).to be_condition("raises an error if the record is missing")
      end
    end

    context "when the keyword only appears inside another word" do
      it "does not match" do
        expect(heuristic).not_to be_condition("behaves differently for guests")
      end
    end

    context "when the description has no condition" do
      it "does not match" do
        expect(heuristic).not_to be_condition("allows deletion")
      end
    end

    context "when a keyword touches a hyphen" do
      it "does not match" do
        expect(heuristic).not_to be_condition("collects the if-node and end-node")
      end
    end

    context "when a keyword is enclosed in quotes" do
      it "does not match" do
        expect(heuristic).not_to be_condition('handles the "if" branch specially')
      end
    end

    context "when a keyword is preceded by a colon (a Ruby symbol literal)" do
      it "does not match" do
        expect(heuristic).not_to be_condition("sets type to :if for the node")
      end
    end

    context "when a keyword touches a slash" do
      it "does not match" do
        expect(heuristic).not_to be_condition("collects the if/end nodes")
      end
    end

    context "when a keyword is parenthesized" do
      it "still matches" do
        expect(heuristic).to be_condition("raises an error (if the input is invalid)")
      end
    end
  end

  context "with an empty keyword list" do
    subject(:heuristic) { described_class.new(keywords: []) }

    it "never matches" do
      expect(heuristic).not_to be_condition("when the user is an admin")
    end
  end
end
