defmodule Evhlegalchat.Segmentation.Anchors do
  @moduledoc """
  Character offset to page mapping utilities.
  
  Provides functions to map character positions to page numbers
  and vice versa using page boundary information.
  """

  @doc """
  Maps a character offset to the corresponding page number.
  
  Returns the page number (1-based) for the given character offset.
  """
  def char_offset_to_page(char_offset, pages) when is_integer(char_offset) and char_offset >= 0 do
    char_offset_to_page_recursive(char_offset, pages, 0, 1)
  end

  @doc """
  Maps a page number to its starting character offset.
  
  Returns the character offset where the page begins.
  """
  def page_to_char_offset(page_num, pages) when is_integer(page_num) and page_num > 0 do
    page_to_char_offset_recursive(page_num, pages, 0, 1)
  end

  @doc """
  Maps a character range to page range.
  
  Returns {start_page, end_page} for the given character range.
  """
  def char_range_to_page_range(start_char, end_char, pages) do
    start_page = char_offset_to_page(start_char, pages)
    end_page = char_offset_to_page(end_char, pages)
    {start_page, end_page}
  end

  @doc """
  Builds a page index map from pages data.
  
  Creates a lookup structure for efficient page boundary queries.
  """
  def build_page_index(pages) do
    pages
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, 0}, fn {page_data, page_num}, {index, cumulative_chars} ->
      char_count = Map.get(page_data, :char_count, 0)
      
      # Map cumulative character ranges to page numbers
      page_boundaries = %{
        start_char: cumulative_chars,
        end_char: cumulative_chars + char_count - 1,
        page_num: page_num,
        char_count: char_count
      }
      
      index = Map.put(index, page_num, page_boundaries)
      {index, cumulative_chars + char_count}
    end)
    |> elem(0)
  end

  @doc """
  Finds the page containing the given character offset using page index.
  
  More efficient than recursive search for large documents.
  """
  def find_page_by_offset(char_offset, page_index) do
    page_index
    |> Enum.find(fn {_page_num, boundaries} ->
      char_offset >= boundaries.start_char and char_offset <= boundaries.end_char
    end)
    |> case do
      {page_num, _boundaries} -> page_num
      nil -> 1  # Fallback to page 1
    end
  end

  @doc """
  Gets page boundaries for a specific page number.
  
  Returns the character range for the given page.
  """
  def get_page_boundaries(page_num, page_index) do
    case Map.get(page_index, page_num) do
      nil -> {0, 0}
      boundaries -> {boundaries.start_char, boundaries.end_char}
    end
  end

  @doc """
  Validates that a character offset is within document bounds.
  
  Returns true if the offset is valid, false otherwise.
  """
  def valid_char_offset?(char_offset, pages) when is_integer(char_offset) do
    total_chars = Enum.reduce(pages, 0, fn page, acc ->
      acc + Map.get(page, :char_count, 0)
    end)
    
    char_offset >= 0 and char_offset < total_chars
  end

  @doc """
  Gets the total character count across all pages.
  """
  def total_char_count(pages) do
    Enum.reduce(pages, 0, fn page, acc ->
      acc + Map.get(page, :char_count, 0)
    end)
  end

  @doc """
  Gets the total page count.
  """
  def total_page_count(pages) do
    length(pages)
  end

  # Private functions

  defp char_offset_to_page_recursive(char_offset, [], _cumulative_chars, current_page) do
    current_page
  end

  defp char_offset_to_page_recursive(char_offset, [page | remaining_pages], cumulative_chars, current_page) do
    page_char_count = Map.get(page, :char_count, 0)
    
    if char_offset < cumulative_chars + page_char_count do
      current_page
    else
      char_offset_to_page_recursive(char_offset, remaining_pages, cumulative_chars + page_char_count, current_page + 1)
    end
  end

  defp page_to_char_offset_recursive(target_page, [], _cumulative_chars, current_page) do
    0  # Fallback if page not found
  end

  defp page_to_char_offset_recursive(target_page, [page | remaining_pages], cumulative_chars, current_page) do
    if current_page == target_page do
      cumulative_chars
    else
      page_char_count = Map.get(page, :char_count, 0)
      page_to_char_offset_recursive(target_page, remaining_pages, cumulative_chars + page_char_count, current_page + 1)
    end
  end
end