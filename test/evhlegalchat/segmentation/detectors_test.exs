defmodule Evhlegalchat.Segmentation.DetectorsTest do
  use ExUnit.Case, async: true
  
  alias Evhlegalchat.Segmentation.Detectors

  describe "detect_candidates/2" do
    test "detects numbered decimal headings" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement...
      
      2. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      """
      
      candidates = Detectors.detect_candidates(text)
      
      numbered_candidates = Enum.filter(candidates, &(&1.type == :numbered_decimal))
      assert length(numbered_candidates) >= 2
      
      first_candidate = Enum.find(numbered_candidates, &(&1.number_label == "1"))
      assert first_candidate.heading_text == "DEFINITIONS"
      assert first_candidate.score > 0.7
    end

    test "detects roman numeral headings" do
      text = """
      I. DEFINITIONS
      
      For purposes of this Agreement...
      
      II. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      """
      
      candidates = Detectors.detect_candidates(text)
      
      roman_candidates = Enum.filter(candidates, &(&1.type == :numbered_roman))
      assert length(roman_candidates) >= 2
      
      first_candidate = Enum.find(roman_candidates, &(&1.number_label == "I"))
      assert first_candidate.heading_text == "DEFINITIONS"
    end

    test "detects all caps headings" do
      text = """
      DEFINITIONS
      
      For purposes of this Agreement...
      
      CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      """
      
      candidates = Detectors.detect_candidates(text)
      
      caps_candidates = Enum.filter(candidates, &(&1.type == :all_caps_heading))
      assert length(caps_candidates) >= 2
      
      first_candidate = Enum.find(caps_candidates, &(&1.heading_text == "DEFINITIONS"))
      assert first_candidate.score > 0.6
    end

    test "detects bullet points" do
      text = """
      SCOPE OF WORK
      
      The Contractor shall provide:
      
      • Software development
      • System integration
      • User training
      """
      
      candidates = Detectors.detect_candidates(text)
      
      bullet_candidates = Enum.filter(candidates, &(&1.type == :bullet_point))
      assert length(bullet_candidates) >= 3
    end

    test "detects exhibit markers" do
      text = """
      EXHIBIT A
      
      Software License Agreement
      
      SCHEDULE 1
      
      Payment Terms
      """
      
      candidates = Detectors.detect_candidates(text)
      
      exhibit_candidates = Enum.filter(candidates, &(&1.type == :exhibit_marker))
      assert length(exhibit_candidates) >= 2
      
      first_candidate = Enum.find(exhibit_candidates, &(&1.heading_text == "EXHIBIT A"))
      assert first_candidate.score > 0.8
    end

    test "detects signature anchors" do
      text = """
      IN WITNESS WHEREOF, the parties have executed this Agreement.
      
      SIGNATURES
      
      Company: ________________
      Employee: _______________
      """
      
      candidates = Detectors.detect_candidates(text)
      
      signature_candidates = Enum.filter(candidates, &(&1.type == :signature_anchor))
      assert length(signature_candidates) >= 2
    end
  end

  describe "scoring functions" do
    test "calculates appropriate scores for different types" do
      text = "1. DEFINITIONS"
      
      candidates = Detectors.detect_candidates(text)
      numbered_candidate = Enum.find(candidates, &(&1.type == :numbered_decimal))
      
      assert numbered_candidate.score > 0.7
      assert numbered_candidate.score <= 1.0
    end

    test "applies length penalties appropriately" do
      short_text = "1. A"
      long_text = "1. This is a very long heading that exceeds reasonable limits and should receive a penalty"
      
      short_candidates = Detectors.detect_candidates(short_text)
      long_candidates = Detectors.detect_candidates(long_text)
      
      short_score = Enum.find(short_candidates, &(&1.type == :numbered_decimal)).score
      long_score = Enum.find(long_candidates, &(&1.type == :numbered_decimal)).score
      
      assert short_score < long_score  # Short headings should be penalized
    end
  end
end