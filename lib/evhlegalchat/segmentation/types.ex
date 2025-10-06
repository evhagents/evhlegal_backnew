defmodule Evhlegalchat.Segmentation.Types do
  @moduledoc """
  Type definitions for the segmentation pipeline.
  
  Defines the core data structures used throughout the segmentation process.
  """

  @doc """
  Represents a detected candidate boundary in the document.
  
  Contains position information, detection metadata, and scoring.
  """
  defmodule Candidate do
    @type t :: %__MODULE__{
      char_offset: non_neg_integer(),
      line_index: non_neg_integer(),
      type: atom(),
      detector: atom(),
      score: float(),
      number_label: String.t() | nil,
      heading_text: String.t() | nil
    }

    defstruct [
      :char_offset,
      :line_index,
      :type,
      :detector,
      :score,
      :number_label,
      :heading_text
    ]
  end

  @doc """
  Represents a finalized clause boundary with complete metadata.
  
  Contains position spans, confidence scores, and anomaly flags.
  """
  defmodule Clause do
    @type t :: %__MODULE__{
      ordinal: pos_integer(),
      number_label: String.t() | nil,
      heading_text: String.t() | nil,
      start_char: non_neg_integer(),
      end_char: non_neg_integer(),
      start_page: pos_integer(),
      end_page: pos_integer(),
      detected_style: atom(),
      confidence_boundary: float(),
      confidence_heading: float(),
      anomaly_flags: [String.t()],
      text_snippet: String.t()
    }

    defstruct [
      :ordinal,
      :number_label,
      :heading_text,
      :start_char,
      :end_char,
      :start_page,
      :end_page,
      :detected_style,
      :confidence_boundary,
      :confidence_heading,
      :anomaly_flags,
      :text_snippet
    ]
  end

  @doc """
  Represents segmentation metrics and statistics.
  
  Contains counts, averages, and quality indicators.
  """
  defmodule Metrics do
    @type t :: %__MODULE__{
      candidate_count: non_neg_integer(),
      accepted_count: non_neg_integer(),
      suppressed_count: non_neg_integer(),
      mean_conf_boundary: float(),
      ocr_used: boolean()
    }

    defstruct [
      :candidate_count,
      :accepted_count,
      :suppressed_count,
      :mean_conf_boundary,
      :ocr_used
    ]
  end

  @doc """
  Represents a segmentation anomaly or issue.
  
  Contains anomaly type and location information.
  """
  defmodule Anomaly do
    @type t :: %__MODULE__{
      type: atom(),
      at: non_neg_integer(),
      severity: :low | :medium | :high,
      description: String.t()
    }

    defstruct [
      :type,
      :at,
      :severity,
      :description
    ]
  end

  @doc """
  Represents a segmentation event for audit trail.
  
  Contains event type and relevant metadata.
  """
  defmodule Event do
    @type t :: %__MODULE__{
      event: atom(),
      timestamp: DateTime.t(),
      detail: map()
    }

    defstruct [
      :event,
      :timestamp,
      :detail
    ]
  end

  @doc """
  Represents the complete segmentation result.
  
  Contains all outputs from the segmentation pipeline.
  """
  defmodule SegResult do
    @type t :: %__MODULE__{
      clauses: [Clause.t()],
      metrics: Metrics.t(),
      anomalies: [Anomaly.t()],
      events: [Event.t()],
      needs_review: boolean()
    }

    defstruct [
      :clauses,
      :metrics,
      :anomalies,
      :events,
      :needs_review
    ]
  end

  # Detected style constants
  @detected_styles [
    :numbered_decimal,      # "1.", "2.1", "3.2.1"
    :numbered_roman,        # "I.", "II.", "III."
    :numbered_alpha,        # "a)", "b)", "c)"
    :bullet_point,          # "•", "-", "*"
    :all_caps_heading,      # "DEFINITIONS", "TERMS AND CONDITIONS"
    :title_case_heading,    # "Definitions", "Terms and Conditions"
    :exhibit_marker,        # "EXHIBIT A", "SCHEDULE 1"
    :signature_anchor,      # "IN WITNESS WHEREOF", "SIGNATURES"
    :unheaded_block         # No clear heading detected
  ]

  @doc """
  Returns all supported detected styles.
  """
  def detected_styles, do: @detected_styles

  @doc """
  Validates that a detected style is supported.
  """
  def valid_detected_style?(style) when style in @detected_styles, do: true
  def valid_detected_style?(_), do: false

  # Anomaly type constants
  @anomaly_types [
    :duplicate_number,      # Same number appears multiple times
    :skipped_number,        # Number sequence has gaps
    :unheaded_block,        # Large text block without heading
    :excessive_short_clause, # Very short clause segments
    :page_regression,       # Clause spans backwards across pages
    :mixed_roman_decimal,   # Mix of roman and decimal numbering
    :all_lowercase_heading, # Heading in all lowercase
    :sparse_boundaries,     # Too few boundaries detected
    :low_confidence_boundaries # Many low-confidence boundaries
  ]

  @doc """
  Returns all supported anomaly types.
  """
  def anomaly_types, do: @anomaly_types

  @doc """
  Validates that an anomaly type is supported.
  """
  def valid_anomaly_type?(type) when type in @anomaly_types, do: true
  def valid_anomaly_type?(_), do: false
end