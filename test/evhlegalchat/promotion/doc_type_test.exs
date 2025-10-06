defmodule Evhlegalchat.Promotion.DocTypeTest do
  use ExUnit.Case, async: true
  alias Evhlegalchat.Promotion.DocType

  test "detects NDA from confidential information keywords" do
    clauses = [
      %{heading_text: "1. Confidential Information", text_snippet: "The parties agree to maintain confidentiality of proprietary information"},
      %{heading_text: "2. Non-Disclosure", text_snippet: "This agreement contains trade secrets and confidential data"}
    ]
    
    assert {:ok, :NDA} = DocType.guess(clauses)
  end

  test "detects SOW from deliverables keywords" do
    clauses = [
      %{heading_text: "1. Scope of Work", text_snippet: "The contractor will deliver the following deliverables"},
      %{heading_text: "2. Milestones", text_snippet: "Project timeline includes key milestones and deliverables"}
    ]
    
    assert {:ok, :SOW} = DocType.guess(clauses)
  end

  test "returns unknown for ambiguous content" do
    clauses = [
      %{heading_text: "1. General Terms", text_snippet: "This document contains general terms and conditions"},
      %{heading_text: "2. Miscellaneous", text_snippet: "Other provisions apply as specified"}
    ]
    
    assert {:unknown, default: :NDA} = DocType.guess(clauses)
  end

  test "penalizes mixed content appropriately" do
    clauses = [
      %{heading_text: "1. Confidential Information", text_snippet: "Confidential data and trade secrets"},
      %{heading_text: "2. Deliverables", text_snippet: "The contractor will deliver specific milestones"}
    ]
    
    # Should default to NDA due to penalty system
    assert {:unknown, default: :NDA} = DocType.guess(clauses)
  end

  test "handles empty clauses list" do
    assert {:unknown, default: :NDA} = DocType.guess([])
  end

  test "handles clauses with nil text" do
    clauses = [
      %{heading_text: nil, text_snippet: nil},
      %{heading_text: "1. Terms", text_snippet: "General terms apply"}
    ]
    
    assert {:unknown, default: :NDA} = DocType.guess(clauses)
  end
end
