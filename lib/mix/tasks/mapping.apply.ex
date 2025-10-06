defmodule Mix.Tasks.Mapping.Apply do
  use Mix.Task
  @shortdoc "Feed JSON facts and run mapping worker"

  @moduledoc """
  mix mapping:apply --agreement 27 --facts priv/samples/facts_27.json
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [agreement: :integer, facts: :string])
    agreement_id = Keyword.fetch!(opts, :agreement)
    facts_path = Keyword.get(opts, :facts)

    if facts_path do
      facts_path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.each(fn attrs ->
        attrs = Map.put(attrs, "agreement_id", agreement_id)
        case Evhlegalchat.Mapping.capture_fact(attrs) do
          {:ok, _} -> :ok
          {:error, cs} -> Mix.shell().error("Invalid fact: #{inspect(cs.errors)}")
        end
      end)
    end

    Evhlegalchat.Mapping.enqueue_worker(agreement_id)
  end

  # keep keys as strings; Ecto changesets accept atom or string keys
end


