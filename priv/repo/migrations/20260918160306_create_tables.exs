defmodule Ucas.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def change do
    create table(:provider, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false, size: 255
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create table(:campus, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider_id, references(:provider, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false, size: 255
    end

    create table(:academic_year) do
      add :year, :string, null: false, size: 4
    end

    create unique_index(:academic_year, [:year])

    create table(:qualification, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false, size: 255
    end

    create table(:study_mode) do
      add :name, :string, null: false, size: 50
    end

    create unique_index(:study_mode, [:name])

    create table(:course, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :provider_id, references(:provider, type: :uuid, on_delete: :delete_all), null: false
      add :code, :string, size: 16
      add :name, :string, null: false, size: 255
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end

    create index(:course, [:provider_id, :code], name: :course_provider_id_code_index)

    create table(:course_study_option, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :course_id, references(:course, type: :uuid, on_delete: :delete_all), null: false

      add :academic_year_id, references(:academic_year, type: :integer, on_delete: :nothing),
        null: false

      add :qualification_id, references(:qualification, type: :uuid, on_delete: :nothing),
        null: false

      add :study_mode_id, references(:study_mode, type: :integer, on_delete: :nothing),
        null: false

      add :campus_id, references(:campus, type: :uuid, on_delete: :nilify_all)
      add :duration, :string, null: false, size: 32
      add :start_date, :string, null: false, size: 64
      add :entry_requirements, :text
      add :created_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
