Newsman NNTP news tool

Newsman is a simple NNTP perl tool that can:
  * Show a list of groups (newsgroups e.g. alt.binaries.linux) which can be filtered by a regular expression (regex)
  * Retrieve and cache headers (in batches) using XOVER minimizing it's memory footprint
  * Download articles to a specified directory
  * yEnc decode those articles if possible.

Requirements:
  * News::NNTPClient (libnews-nntpclient-perl)
  * DBD::SQLite (libdbd-sqlite3-perl)
  * DateTime::Format::Mail (libdatetime-format-mail-perl)

Where newsman shines is as an nzb downloader.  For example, you could automate newsman to go get the .nzb files listed on a news server and then put them into the directory that is watched by SABnzbd (http://sabnzbd.org/) for downloading.

If instructed (and by default), the newsman tool uses a very small memory footprint using a batch retrieval mechanism (unlike some others that claim to have been redesigned for a lesser footprint) but assumes disk space is not a problem.

For a quickstart, see the bottom of the tool help (newsman -h).
