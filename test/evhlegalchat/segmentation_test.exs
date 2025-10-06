defmodule Evhlegalchat.SegmentationTest do
  use ExUnit.Case, async: true
  
  alias Evhlegalchat.Segmentation

  describe "run/3" do
    test "processes simple numbered document" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement, the following terms shall have the meanings set forth below:
      
      1.1 "Company" means ABC Corporation.
      
      1.2 "Employee" means John Smith.
      
      2. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain the confidentiality of all Confidential Information.
      
      2.1 Employee shall not disclose Confidential Information to any third party.
      
      2.2 Employee shall use Confidential Information solely for the benefit of Company.
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      opts = [
        segmentation_version: "seg-v1.0",
        ocr_used: false,
        ocr_confidence: 1.0
      ]
      
      result = Segmentation.run(text, pages, opts)
      
      assert length(result.clauses) >= 3  # At least 3 main sections
      assert result.metrics.candidate_count > 0
      assert result.metrics.accepted_count > 0
      assert result.needs_review == false
      
      # Check first clause
      first_clause = Enum.find(result.clauses, &(&1.ordinal == 1))
      assert first_clause.number_label == "1"
      assert first_clause.heading_text == "DEFINITIONS"
      assert first_clause.start_page == 1
      assert first_clause.end_page == 1
    end

    test "detects anomalies in duplicate numbering" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement...
      
      5. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      
      5. CONFIDENTIALITY OBLIGATIONS (DUPLICATE)
      
      Employee agrees to maintain...
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      result = Segmentation.run(text, pages, [])
      
      # Should detect duplicate number anomaly
      duplicate_anomalies = Enum.filter(result.anomalies, &(&1.type == :duplicate_number))
      assert length(duplicate_anomalies) > 0
      
      # Should detect skipped number anomaly
      skipped_anomalies = Enum.filter(result.anomalies, &(&1.type == :skipped_number))
      assert length(skipped_anomalies) > 0
    end

    test "processes bullet point document" do
      text = """
      SCOPE OF WORK
      
      The Contractor shall provide:
      
      • Software development and implementation
      • System integration and testing
      • User training and documentation
      • Ongoing maintenance and support
      
      DELIVERABLES
      
      The Contractor shall deliver:
      
      • Complete software application
      • Technical documentation
      • User manuals and guides
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      result = Segmentation.run(text, pages, [])
      
      assert length(result.clauses) >= 2  # At least 2 main sections
      
      # Check for bullet point clauses
      bullet_clauses = Enum.filter(result.clauses, &(&1.detected_style == :bullet_point))
      assert length(bullet_clauses) > 0
    end

    test "handles OCR quality issues" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement...
      
      2. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      opts = [
        ocr_used: true,
        ocr_confidence: 0.5  # Low OCR confidence
      ]
      
      result = Segmentation.run(text, pages, opts)
      
      # Should flag for review due to low OCR confidence
      assert result.needs_review == true
      
      # Should have OCR-related anomalies
      ocr_anomalies = Enum.filter(result.anomalies, &(&1.type == :low_confidence_boundaries))
      assert length(ocr_anomalies) > 0
    end

    test "handles sparse boundaries in large document" do
      # Create a large document with few boundaries
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement, the following terms shall have the meanings set forth below.
      This is a very long section with lots of text but no clear sub-headings.
      The text continues for many paragraphs without any numbered or bulleted sections.
      This creates a situation where the document has very few boundaries relative to its size.
      """
      
      # Simulate a large document by creating multiple pages
      pages = Enum.map(1..6, fn page_num ->
        %{page: page_num, char_count: 200}
      end)
      
      result = Segmentation.run(text, pages, [])
      
      # Should flag for review due to sparse boundaries
      assert result.needs_review == true
      
      # Should have sparse boundaries anomaly
      sparse_anomalies = Enum.filter(result.anomalies, &(&1.type == :sparse_boundaries))
      assert length(sparse_anomalies) > 0
    end

    test "generates appropriate metrics" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement...
      
      2. CONFIDENTIALITY OBLIGATIONS
      
      Employee agrees to maintain...
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      result = Segmentation.run(text, pages, [])
      
      assert result.metrics.candidate_count > 0
      assert result.metrics.accepted_count > 0
      assert result.metrics.suppressed_count >= 0
      assert result.metrics.mean_conf_boundary > 0.0
      assert result.metrics.mean_conf_boundary <= 1.0
      assert result.metrics.ocr_used == false
    end

    test "generates appropriate events" do
      text = """
      1. DEFINITIONS
      
      For purposes of this Agreement...
      """
      
      pages = [%{page: 1, char_count: String.length(text)}]
      
      result = Segmentation.run(text, pages, [])
      
      assert length(result.events) > 0
      
      # Should have boundary detection event
      boundary_events = Enum.filter(result.events, &(&1.event == :boundary_detected))
      assert length(boundary_events) > 0
      
      # Should have acceptance event
      acceptance_events = Enum.filter(result.events, &(&1.event == :boundaries_accepted))
      assert length(acceptance_events) > 0
    end
  end
end
