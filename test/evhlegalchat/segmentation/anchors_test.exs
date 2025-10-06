defmodule Evhlegalchat.Segmentation.AnchorsTest do
  use ExUnit.Case, async: true
  
  alias Evhlegalchat.Segmentation.Anchors

  describe "char_offset_to_page/2" do
    test "maps character offsets to correct page numbers" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150},
        %{page: 3, char_count: 200}
      ]
      
      assert Anchors.char_offset_to_page(0, pages) == 1
      assert Anchors.char_offset_to_page(50, pages) == 1
      assert Anchors.char_offset_to_page(100, pages) == 2
      assert Anchors.char_offset_to_page(200, pages) == 3
      assert Anchors.char_offset_to_page(400, pages) == 3  # Beyond last page
    end

    test "handles single page documents" do
      pages = [%{page: 1, char_count: 100}]
      
      assert Anchors.char_offset_to_page(0, pages) == 1
      assert Anchors.char_offset_to_page(50, pages) == 1
      assert Anchors.char_offset_to_page(99, pages) == 1
    end
  end

  describe "page_to_char_offset/2" do
    test "maps page numbers to starting character offsets" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150},
        %{page: 3, char_count: 200}
      ]
      
      assert Anchors.page_to_char_offset(1, pages) == 0
      assert Anchors.page_to_char_offset(2, pages) == 100
      assert Anchors.page_to_char_offset(3, pages) == 250
    end
  end

  describe "char_range_to_page_range/3" do
    test "maps character ranges to page ranges" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150},
        %{page: 3, char_count: 200}
      ]
      
      assert Anchors.char_range_to_page_range(50, 120, pages) == {1, 2}
      assert Anchors.char_range_to_page_range(200, 300, pages) == {3, 3}
    end
  end

  describe "build_page_index/1" do
    test "builds correct page index structure" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150}
      ]
      
      index = Anchors.build_page_index(pages)
      
      assert Map.get(index, 1) == %{
        start_char: 0,
        end_char: 99,
        page_num: 1,
        char_count: 100
      }
      
      assert Map.get(index, 2) == %{
        start_char: 100,
        end_char: 249,
        page_num: 2,
        char_count: 150
      }
    end
  end

  describe "find_page_by_offset/2" do
    test "finds correct page using page index" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150}
      ]
      
      index = Anchors.build_page_index(pages)
      
      assert Anchors.find_page_by_offset(50, index) == 1
      assert Anchors.find_page_by_offset(150, index) == 2
      assert Anchors.find_page_by_offset(300, index) == 1  # Fallback
    end
  end

  describe "validation functions" do
    test "validates character offsets correctly" do
      pages = [%{page: 1, char_count: 100}]
      
      assert Anchors.valid_char_offset?(0, pages) == true
      assert Anchors.valid_char_offset?(50, pages) == true
      assert Anchors.valid_char_offset?(99, pages) == true
      assert Anchors.valid_char_offset?(100, pages) == false
      assert Anchors.valid_char_offset?(-1, pages) == false
    end

    test "calculates total character count" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150},
        %{page: 3, char_count: 200}
      ]
      
      assert Anchors.total_char_count(pages) == 450
    end

    test "calculates total page count" do
      pages = [
        %{page: 1, char_count: 100},
        %{page: 2, char_count: 150}
      ]
      
      assert Anchors.total_page_count(pages) == 2
    end
  end
end
