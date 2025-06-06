defmodule Mix.Tasks.Sbom.Cyclonedx do
  @shortdoc "Generates CycloneDX SBoM"

  use Mix.Task
  import Mix.Generator

  @schema_versions ["1.6", "1.5", "1.4", "1.3", "1.2", "1.1"]

  @default_path "bom.xml"
  @default_path_json "bom.json"
  @default_schema "1.6"
  @default_classification "application"

  @default_opts [
    schema: @default_schema,
    classification: @default_classification
  ]

  @moduledoc """
  Generates a Software Bill-of-Materials (SBoM) in CycloneDX format.

  ## Options

    * `--output` (`-o`): the full path to the SBoM output file (default:
      #{@default_path})
    * `--force` (`-f`): overwrite existing files without prompting for
      confirmation
    * `--dev` (`-d`): include dependencies for non-production environments
      (including `dev`, `test` or `docs`); by default only dependencies for
      MIX_ENV=prod are returned
    * `--recurse` (`-r`): in an umbrella project, generate individual output
      files for each application, rather than a single file for the entire
      project
    * `--schema` (`-s`): schema version to be used, defaults to
      "#{@default_schema}"
    * `--format` (`-t`): output format: xml or json; defaults to "xml", unless
      the output path ends with ".json"
    * `--classification` (`-c`): the project classification, e.g. "application",
      "library", "framework"; defaults to "#{@default_classification}"

  """

  @doc false
  @impl Mix.Task
  def run(all_args) do
    {opts, _args} =
      OptionParser.parse!(
        all_args,
        aliases: [
          o: :output,
          f: :force,
          d: :dev,
          r: :recurse,
          s: :schema,
          t: :format,
          c: :classification
        ],
        strict: [
          output: :string,
          force: :boolean,
          dev: :boolean,
          recurse: :boolean,
          schema: :string,
          format: :string,
          classification: :string
        ]
      )

    opts =
      @default_opts
      |> Keyword.merge(opts)
      |> update_output_path_and_format!()

    validate_schema!(opts[:schema])

    output_path = opts[:output]
    environment = (!opts[:dev] && :prod) || nil
    apps = Mix.Project.apps_paths()

    if opts[:recurse] && apps do
      Enum.each(apps, &generate_bom(&1, output_path, environment, opts[:force]))
    else
      generate_bom(output_path, environment, opts)
    end
  end

  defp generate_bom(output_path, environment, opts) do
    classification = opts[:classification]

    case SBoM.components_for_project(classification, environment) do
      {:ok, components} ->
        xml = SBoM.CycloneDX.bom(components, opts)
        create_file(output_path, xml, force: opts[:force])

      {:error, :unresolved_dependency} ->
        dependency_error()
    end
  end

  defp generate_bom({app, path}, output_path, environment, force) do
    Mix.Project.in_project(app, path, fn _module ->
      generate_bom(output_path, environment, force)
    end)
  end

  defp dependency_error do
    shell = Mix.shell()
    shell.error("Unchecked dependencies; please run `mix deps.get`")
    Mix.raise("Can't continue due to errors on dependencies")
  end

  defp update_output_path_and_format!(opts) do
    {output, format} =
      case {opts[:output], opts[:format]} do
        {nil, nil} ->
          {@default_path, format_from_path(@default_path)}

        {output, nil} ->
          {output, format_from_path(output)}

        {nil, "xml"} ->
          {@default_path, "xml"}

        {nil, "json"} ->
          {@default_path_json, "json"}

        {output, format} when format in ["xml", "json"] ->
          {output, format}

        {_, format} ->
          Mix.raise("Unsupported output format: #{format}")
      end

    Keyword.merge(opts, output: output, format: format)
  end

  defp format_from_path(path) do
    case Path.extname(path) do
      ".json" -> "json"
      _ -> "xml"
    end
  end

  defp validate_schema!(schema) do
    if schema not in @schema_versions do
      shell = Mix.shell()

      shell.error(
        "invalid cyclonedx schema version, available versions are #{@schema_versions |> Enum.join(", ")}"
      )

      Mix.raise("Give correct cyclonedx schema version to continue.")
    end
  end
end
