#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <string.h>
#ifdef HAVE_STRINGS_H
#include <strings.h>
#endif
#include <stdlib.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#ifdef HAVE_POLL
# include <sys/poll.h>
#endif
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif
void syntax( char * cmd )
{
  printf( "Syntax: %s [--help] [--version] <url> < <file>\n", cmd );
  exit(1);
}

char* encode_base64( char *src, int len )
{
  static char base64tab[64] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  static char buff[1024];
  char *dest;
  int cnt = (len+2)/3;
  dest = buff;
  while( cnt-- )
  {
    int d = *src++<<8;
    d = (*src++|d)<<8;
    d |= *src++;
    /* Output in encoded from to dest */
    *dest++ = base64tab[d>>18];
    *dest++ = base64tab[(d>>12)&63];
    *dest++ = base64tab[(d>>6)&63];
    *dest++ = base64tab[d&63];
  }
  switch (len%3)
  {
    case 1:
      *--dest = '=';
    case 2:
      *--dest = '=';
  }
  return buff;
}

void put_file( char *url, int len )
{
  int i, port=80, fd;
  char *host, *file, *id, buffer[4711], buffer2[1024], *p;
  struct hostent *hent;
  struct sockaddr_in addr;
  if( strncmp( url, "http://", 7 ) )
  {
    printf("Only HTTP urls are supported\n");
    exit(1);
  }
  id = 0;
  host = url + 7;
  for( i = 0; i<strlen(host); i++ )
    if( host[i] == '/' )
    {
      file = host+i+1;
      host[i]=0;
    }

  for( i = 0; i<strlen(host); i++ )
    if( host[i] == '@' )
    {
      id = host;
      host[i]=0;
      host = host+i+1;
      break;
    }

  for( i = 0; i<strlen(host); i++ )
    if( host[i] == ':' )
    {
      port = atoi( host+i+1 );
      host[i]=0;
      break;
    }
  
  printf("Host: %s\n", host );
  printf("File: %s\n", file );
  printf("Port: %d\n", port );
  if( id ) printf("ID  : %s\n", id );
  printf("flen: %d\n", len );


  /* look up host */
  hent = gethostbyname( host );
  if( !hent )
  {
    perror("gethostbyname");
    exit(1);
  }

  printf( "IP  : %d.%d.%d.%d\n",
	  ((unsigned char*)hent->h_addr_list[0])[0],
	  ((unsigned char*)hent->h_addr_list[0])[1],
	  ((unsigned char*)hent->h_addr_list[0])[2],
	  ((unsigned char*)hent->h_addr_list[0])[3]
	);

  if( strlen(file) > 200 )
    printf("Too long filename\n" );
  if( strlen(host) > 200 )
    printf("Too long hostname\n" );
  if( id && strlen(id) > 200 )
    printf("Too long userid\n" );
  
  /* connect */
  fd = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family = AF_INET;
  memcpy((char*)&addr.sin_addr, hent->h_addr_list[0], 4);
  addr.sin_port = htons( port );

  printf("Connecting...");
  fflush(stdout);
  if( connect( fd, (struct sockaddr *)&addr, sizeof(addr) ) )
  {
    perror("connect" );
    exit(1);
  }
  printf("done\n");

  /* build request */

  buffer2[0]=0;
  if( id )
  {
    strcpy( buffer, id );
    buffer[strlen(buffer)+1]=0;
    sprintf( buffer2, "Authorization: Basic %s\r\n",
	     encode_base64(buffer,strlen(id)) );
  }

  
  printf("sending request.." );
  fflush(stdout);
  
  sprintf( buffer,
	   "PUT /%s HTTP/1.0\r\n"
	   "Host: %s:%d\r\n%s"
	   "User-Agent: simple-put\r\n"
	   "Content-Type: application/octet-stream\r\n"
	   "Content-Length: %d\r\n"
	   "\r\n",

	   file, host, port, buffer2, len );

  
  i = strlen(buffer);
  p = buffer;
  while( i > 0 )
  {
    int w = write( fd, buffer, strlen(buffer) );
    i -= w;
    p += w;
    if( w <= 0 )
    {
      perror("write");
      exit(1);
    }
  }
  printf("done\n");
  
  i = 0;
  printf("sending data.." );
  fflush(stdout);
  while( i < len )
  {
    int b, o;
    b = read( 0, buffer, 4711 );
    if( b <= 0  )
    {
      perror("read");
      exit(1);
    }
    i+=b;
    o = 0;
    while( b )
    {
      int w = write( fd, buffer+o, b );
      if( w <= 0 )
      {
	perror("write");
	exit(1);
      }
      o += w;
      b -= w;
    }
  }
  printf("done\n");

  printf("Reading reply...");
  fflush(stdout);

  {
    char *x, *y;
    int errorcode, r;
    int rpos = 0;

    while( 1 )
    {
#ifndef HAVE_POLL
      fd_set rs;
      struct timeval timeout;
      timeout.tv_sec = 20;
      timeout.tv_usec = 0;
      FD_SET( fd, &rs );
      if( select( fd+1, &rs, 0, 0, &timeout ) != 1 )
#else
      struct pollfd fds[1];
      fds[0].fd = fd;
      fds[0].events = POLLIN;
      if( poll( fds, 1, 20000 ) != 1 )
#endif      
      {
        printf("Timeout\n");
        exit(1);
      }
      r = read( fd, buffer+rpos, 4711 );
      if (r == 0)
      {
	printf("End of file while looking for first line\n");
	exit(1);
      }
      if (r < 0)
      {
	perror("read");
	exit(1);
      }
      rpos += r;
      if( x=strchr( buffer, '\n' ) )
      {
        *x = 0;
        if( y=strchr( buffer, '\r' ) )
          *y = 0;
        y = strchr( buffer, ' ' )+1; 

        if( !y )
        {
          printf("Illegal response from server: %s\n", buffer );
          exit( 1 );
        }
        errorcode = atoi(y);
        x = strchr( y, ' ' )+1;
        switch( errorcode/100 )
        {
         case 2:
	   printf("done\n");
	   break;
         default:
           printf(" error %d: %s\n", errorcode, x?x:y );
           exit(1);
           break;
        }
        exit(0);
      }
      else if( rpos > 4711 )
      {
        printf("End of buffer while looking for first line\n");
        exit(1);
      }
    }
  }
}


int main( int argc, char *argv[] )
{
  struct stat st;
  int i;
  
  if( fstat( 0, &st ) )
  {
    perror("fstat");
    syntax(argv[0]);
  }  

  for( i = 1; i<argc; i++ )
  {
    if( !strcmp( argv[i], "--help" ) )
      syntax(argv[i]);
    if( !strcmp( argv[i], "--version" ) )
    {
      printf( "%s\n", "$Id: put.c,v 1.14 2003/01/12 21:14:16 ceder Exp $" );
      exit(0);
    }
    if( (st.st_mode & S_IFMT) != S_IFREG )
    {
      printf("Stdin is not a file!\n");
      syntax( argv[0] );
      exit(1);
    }
    put_file( argv[i], st.st_size );
    exit(0);
  }
  syntax( argv[0] );
  return 0; /* keep gcc happy. */
}
