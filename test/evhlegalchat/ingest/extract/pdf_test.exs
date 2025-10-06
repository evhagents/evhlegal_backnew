defmodule Evhlegalchat.Ingest.Extract.PDFTest do
  use ExUnit.Case, async: true
  
  alias Evhlegalchat.Ingest.Extract.PDF

  describe "PDF extraction" do
    test "extracts text from searchable PDF" do
      temp_dir = System.tmp_dir!()
      
      # Create a minimal PDF with some text
      pdf_content = create_minimal_pdf()
      pdf_path = Path.join(temp_dir, "sample.pdf")
      File.write!(pdf_path, pdf_content)
      
      try do
        case PDF.extract(pdf_path, temp_dir) do
          {:ok, result} ->
            assert result.page_count >= 1
            assert result.char_count > 0
            assert result.ocr == false
            assert String.length(result.text) > 0
            assert is_list(result.pages)
            assert length(result.pages) == result.page_count
            
          # If pdftotext is not available, skip test
          {:error, {:tool_missing, [:pdftotext]}} ->
            raise "PDF extraction test skipped: pdftotext not available"
          
          {:error, reason} ->
            flunk("PDF extraction failed: #{inspect(reason)}")
        end
      finally
        File.rm_if_exists(pdf_path)
      end
    end

    test "validates file size limits" do
      temp_dir = System.tmp_dir!()
      
      # Create a large dummy file
      large_content = :crypto.strong_rand_bytes(200_000_000)  # 200MB
      large_file = Path.join(temp_dir, "large.pdf")
      File.write!(large_file, large_content)
      
      try do
        {:error, :file_too_large} = PDF.extract_(large_file, temp_dir)
      finally
        File.rm_if_exists(large_file)
      end
    end

    test "validates page count limits" do
      temp_dir = System.tmp_dir!()
      
      # This would require a PDF with >1000 pages, which is hard to create in tests
      # For now, just test that the validation exists
      
      %PDF{
        page_count: 1001,
        char_count: 1000,
        text: "test content"
      } = struct(PDF, %{
        page_count: 1001,
        char_count: 1000,
        text: "test content",
        pages: [],
        word_count: 10,
        ocr: false,
        ocr_confidence: nil,
        tools_used: %{},
        previews_generated: false
      })
      
      # The actual validation happens in the extraction flow
      assert PDF.validate_page_count.(1001) == {:error, {:too_many_pages, 1001}}
    end

    test "handles OCR heuristic correctly" do
      result_low_chars = PDF.build_result("Short", [], 1, true, 0.8, %{tesseract: true})
      assert result_low_chars.ocr == true
      assert result_low_chars.ocr_confidence == 0.8
      
      result_high_chars = PDF.build_result("Long content with many characters", [], 1, false, nil, %{pdftotext: true})
      assert result_high_chars.ocr == false
      assert result_high_chars.ocr_confidence == nil
    end

    test "computes metrics correctly" do
      result = PDF.build_result("Hello world", [%{page: 1, text: "Hello world", char_count: 11}], 1, false, nil, %{pdftotext ("0.1.0")]})
      
      assert result.page_count == 1
      assert result.char_count == 11
      assert result.word_count >= 2
      assert result.ocr == false
      assert is_map(result.tools_used)
    end
  end

  # Helper functions

  defp create_minimal_pdf do
    # Minimal PDF content with some text
    # This creates a valid PDF structure
    """
    %PDF-1.4
    1 0 obj <<
    /Length 50
    >>
    stream
    BT
    /F1 12 Tf
    72 720 Td
    (Sample PDF text content) Tj
    ET
    endstream
    endobj
    
    xref
    0 2
    0000000000 65535 f 
    0000000056 00000 n 
    trailer <<
    /Size 2
    /Root 1 0 R
    >>
    startxref
    158
    %%EOF
    """
  end
end
