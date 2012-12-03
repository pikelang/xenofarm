// Move a file or directory from from to to.
//
// Attempts to use the builtin mv() function, but has a fallback to
// Stdio.recursive_mv() in case we are moving across filesystems.
bool mv(string from, string to)
{
  // Try the builtin mv first.
  if( predef::mv( from, to ) )
    return true;

  // If that failed, try Stdio.recursive_mv, which can handle
  // cross-filesystem moves.
  if( Stdio.recursive_mv( from, to ) )
    return true;

  return false;
}
