import { Action, ActionPanel, Icon, List } from "@raycast/api";
import { showFailureToast, usePromise } from "@raycast/utils";

import { fetchICloudPhotoAlbums } from "@/icloud-photos/fetch-albums";
import { formatAlbumMediaSummary } from "@/icloud-photos/formatters";

export default function Command() {
  const {
    isLoading,
    data: albums = [],
    error,
    revalidate,
  } = usePromise(fetchICloudPhotoAlbums, [], {
    onError(error) {
      showFailureToast(error, { title: "Could not load iCloud Photos albums" });
    },
  });

  return (
    <List isLoading={isLoading} navigationTitle="Organize iCloud Photos">
      {error ? (
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="Could not load albums"
          description={error.message}
          actions={
            <ActionPanel>
              <Action title="Retry" icon={Icon.ArrowClockwise} onAction={() => revalidate()} />
            </ActionPanel>
          }
        />
      ) : albums.length === 0 && !isLoading ? (
        <List.EmptyView
          icon={Icon.Image}
          title="No albums found"
          description="No non-empty albums without the _zgrane suffix were found in Photos."
        />
      ) : (
        albums.map(album => (
          <List.Item
            key={album.name}
            icon={Icon.Folder}
            title={album.name}
            subtitle={formatAlbumMediaSummary(album)}
            actions={
              <ActionPanel>
                <Action.CopyToClipboard content={album.name} title="Copy Album Name" />
                <Action.CopyToClipboard content={String(album.mediaCount)} title="Copy Media Count" />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
