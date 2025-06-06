defmodule Ash.Test.Policy.RbacTest do
  @doc false
  use ExUnit.Case

  require Ash.Query

  alias Ash.Test.Support.PolicyRbac.{File, Membership, Organization, User}

  setup do
    [
      user: Ash.create!(Ash.Changeset.for_create(User, :create), authorize?: false),
      org: Ash.create!(Ash.Changeset.for_create(Organization, :create), authorize?: false)
    ]
  end

  test "if the actor has no permissions, they can't see anything", %{
    user: user,
    org: org
  } do
    create_file(org, "foo")
    create_file(org, "bar")
    create_file(org, "baz")

    assert Ash.read!(File, actor: user) == []
  end

  test "if the actor has permission to read a file, they can only read that file", %{
    user: user,
    org: org
  } do
    file_with_access = create_file(org, "foo")
    give_role(user, org, :viewer, :file, file_with_access.id)
    create_file(org, "bar")
    create_file(org, "baz")

    assert [%{name: "foo"}] = Ash.read!(File, actor: user)
  end

  test "query params on relation are passed correctly to the policy", %{
    user: user,
    org: org
  } do
    user = Map.put(user, :rel_check, true)

    file_with_access = create_file(org, "foo")
    give_role(user, org, :viewer, :file, file_with_access.id)
    create_file(org, "bar")
    create_file(org, "baz")

    # select a forbidden field
    query =
      Organization
      |> Ash.Query.filter(id == ^org.id)
      |> Ash.Query.load(files: File |> Ash.Query.select([:forbidden]))

    assert [%{files: []}] = Ash.read!(query, actor: user)

    # specify no select (everything is selected)
    query =
      Organization
      |> Ash.Query.filter(id == ^org.id)
      |> Ash.Query.load([:files])

    assert [%{files: []}] = Ash.read!(query, actor: user)

    # select only an allowed field
    query =
      Organization
      |> Ash.Query.filter(id == ^org.id)
      |> Ash.Query.load(files: File |> Ash.Query.select([:id]))

    assert [%Organization{files: [%File{id: id}]}] = Ash.read!(query, actor: user)
    assert id == file_with_access.id
  end

  test "unauthorized if no policy is defined", %{user: user} do
    assert_raise Ash.Error.Forbidden, fn ->
      Ash.read!(User, actor: user) == []
    end
  end

  test "if the action can be performed, the can utility should return true", %{
    user: user,
    org: org
  } do
    file_with_access = create_file(org, "foo")
    give_role(user, org, :viewer, :file, file_with_access.id)
    file1 = create_file(org, "bar")
    file2 = create_file(org, "baz")

    assert Ash.can?({File, :read}, user)
    refute Ash.can?({File, :read}, user, data: [file1, file2])
    assert Ash.can?({File, :read}, user, data: file_with_access)

    assert Ash.can?({File, :read, %{}}, user)
    refute Ash.can?({File, :read, %{}}, user, data: [file1, file2])
    assert Ash.can?({File, :read, %{}}, user, data: file_with_access)

    assert Ash.can?({File, :get_by_id, %{id: file_with_access.id}}, user, data: file_with_access)
    refute Ash.can?({File, :get_by_id, %{id: file1.id}}, user, data: file1)
    refute Ash.can?({File, :get_by_id, %{id: file2.id}}, user, data: file2)

    assert File.can_get_by_id?(user, file_with_access.id, data: file_with_access)
    refute File.can_get_by_id?(user, file1.id, data: file1)
    refute File.can_get_by_id?(user, file2.id, data: file2)
  end

  test "if the query can be performed, the can utility should return true", %{
    user: user,
    org: org
  } do
    file_with_access = create_file(org, "foo")
    give_role(user, org, :viewer, :file, file_with_access.id)
    create_file(org, "bar")
    create_file(org, "baz")

    query = Ash.Query.for_read(File, :read)

    assert Ash.can?(query, user)
  end

  test "if the changeset can be performed, the can utility should return true", %{
    user: user,
    org: org
  } do
    changeset =
      File
      |> Ash.Changeset.for_create(:create, %{name: "bar"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)

    assert Ash.can?(changeset, user)
  end

  test "if the update can be performed with a filter, the can utility should return true", %{
    user: user,
    org: org
  } do
    file_with_access = create_file(org, "foo")
    give_role(user, org, :admin, :file, file_with_access.id)

    changeset = Ash.Changeset.for_update(file_with_access, :update, %{name: "bar"})

    assert Ash.can?(changeset, user)
  end

  defp give_role(user, org, role, resource, resource_id) do
    Membership
    |> Ash.Changeset.for_create(:create, %{
      role: role,
      resource: resource,
      resource_id: resource_id
    })
    |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
    |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
    |> Ash.create!(authorize?: false)
  end

  defp create_file(org, name) do
    File
    |> Ash.Changeset.for_create(:create, %{name: name})
    |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
    |> Ash.create!(authorize?: false)
  end
end
