export const FETCH_ALBUMS_SCRIPT = `
on videoCountOf(anAlbum, videoExts)
  tell application "Photos"
    set videoCount to 0
    repeat with ext in videoExts
      set videoCount to videoCount + (count (media items of anAlbum whose filename ends with ext))
    end repeat
    return videoCount
  end tell
end videoCountOf

on collectAlbums(parentContainer, albumList, fieldDelimiter, videoExts)
  tell application "Photos"
    using terms from application "Photos"
      tell parentContainer
        repeat with anAlbum in albums
          set albumName to name of anAlbum
          if albumName does not end with "_zgrane" then
            try
              set mediaCount to count of media items of anAlbum
            on error
              set mediaCount to 0
            end try
            if mediaCount > 0 then
              set videoCount to my videoCountOf(anAlbum, videoExts)
              set photoCount to mediaCount - videoCount
              set end of albumList to albumName & fieldDelimiter & (mediaCount as string) & fieldDelimiter & (photoCount as string) & fieldDelimiter & (videoCount as string)
            end if
          end if
        end repeat
        repeat with aFolder in folders
          my collectAlbums(aFolder, albumList, fieldDelimiter, videoExts)
        end repeat
      end tell
    end using terms from
  end tell
end collectAlbums

on run argv
  set fieldDelimiter to item 1 of argv
  set AppleScript's text item delimiters to ","
  set videoExts to text items of (item 2 of argv)
  set AppleScript's text item delimiters to ""

  tell application "Photos"
    set albumList to {}
    my collectAlbums(it, albumList, fieldDelimiter, videoExts)
  end tell

  set AppleScript's text item delimiters to linefeed
  set output to albumList as string
  set AppleScript's text item delimiters to ""
  return output
end run
`;
