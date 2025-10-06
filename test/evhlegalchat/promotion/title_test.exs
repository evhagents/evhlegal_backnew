defmodule Evhlegalchat.Promotion.TitleTest do
  use ExUnit.Case, async: true
  alias Evhlegalchat.Promotion.Title

  test "derives title from substantial clause heading" do
    clauses = [
      %{heading_text: "1. Non-Disclosure Agreement", text_snippet: "This agreement governs confidential information"},
      %{heading_text: "2. Definitions", text_snippet: "Terms defined herein"}
    ]
    
    assert {:ok, "Non-Disclosure Agreement"} = Title.derive(clauses, "contract.pdf")
  end

  test "skips numeric-only headings" do
    clauses = [
      %{heading_text: "1.", text_snippet: "First section"},
      %{heading_text: "2. Important Agreement Title", text_snippet: "This is the main agreement"}
    ]
    
    assert {:ok, "Important Agreement Title"} = Title.derive(clauses, "contract.pdf")
  end

  test "falls back to filename when no substantial heading" do
    clauses = [
      %{heading_text: "1.", text_snippet: "First section"},
      %{heading_text: "2.", text_snippet: "Second section"}
    ]
    
    assert {:fallback, "Non Disclosure Agreement"} = Title.derive(clauses, "Non-Disclosure_Agreement.pdf")
  end

  test "cleans filename separators" do
    clauses = [%{heading_text: "1.", text_snippet: "Section"}]
    
    assert {:fallback, "Statement of Work"} = Title.derive(clauses, "Statement-of-Work_v2.pdf")
  end

  test "handles empty filename gracefully" do
    clauses = [%{heading_text: "1.", text_snippet: "Section"}]
    
    assert {:fallback, "Untitled Document"} = Title.derive(clauses, "")
  end

  test "trims and normalizes whitespace in titles" do
    clauses = [
      %{heading_text: "  1.   Non-Disclosure   Agreement   ", text_snippet: "Content"}
    ]
    
    assert {:ok, "Non-Disclosure Agreement"} = Title.derive(clauses, "contract.pdf")
  end

  test "removes leading numbers and punctuation" do
    clauses = [
      %{heading_text: "1.1. Non-Disclosure Agreement", text_snippet: "Content"}
    ]
    
    assert {:ok, "Non-Disclosure Agreement"} = Title.derive(clauses, "contract.pdf")
  end

  test "handles clauses with nil headings" do
    clauses = [
      %{heading_text: nil, text_snippet: "Content"},
      %{heading_text: "2. Valid Title", text_snippet: "More content"}
    ]
    
    assert {:ok, "Valid Title"} = Title.derive(clauses, "contract.pdf")
  end

  test "respects length limits for substantial headings" do
    clauses = [
      %{heading_text: "1. " <> String.duplicate("A", 150), text_snippet: "Content"}
    ]
    
    assert {:fallback, "contract"} = Title.derive(clauses, "contract.pdf")
  end
end
