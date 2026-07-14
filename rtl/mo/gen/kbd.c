/*
Generates keyboard mapping tables


*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

//----------------------------------------------------------------------------
// FILE
char map[100*1000];
int  maplen;

//----------------------------------------------------------------------------
//TREE
struct cons {
    char *cars; // CAR as string
    int   car;  // CAR as pointer
    int   cdr;
};
const int NIL = 0;

struct cons list[3000];
int lastn;

/*
    cons :
        cars = string
        car  = 0
        cdr  = next cons / NIL

        cars = NULL
        car  = cons
        cdr  = next cons / NIL

cars : donnée : char * ou pointeur sur sous-chaine
cdr : pointeur sur suite chaine ou fin = 0
*/    

#define cars(i) (list[i].cars)
#define car(i)  (list[i].car)
#define cdr(i)  (list[i].cdr)

//-----------------------------------------------------------------------------
// RAW KEYCODES to packed keycodes
uint8_t keys[512];

// Symbols for each packed keycode
struct keymap {
    char *ps2;
};

struct keymap maps[128];

// Symbol for each TO-MO keyboard key
struct tomokey {
    uint8_t pos; // Code HEX
    uint8_t tag; // Marquage
    char *key; // Touche
};

struct tomokey9 {
    uint8_t pos;
    uint8_t pos_s;  // SHIFT
    uint8_t pos_c;  // CONTROL
    uint8_t pos_sc; // SHIFT + CONTROL
    uint8_t tag;
    char *key; // Touche
};

// Remapping for PS2 -> TOMO key names
struct remap {
    char    *ps2;
    char    *tomo;
    uint8_t tag;
};

struct tomokey  mo5[100];
struct tomokey  mo6[100];
struct tomokey  to7[100];
struct tomokey  to8[100];
struct tomokey9 to9[100];
struct tomokey9 to9p[100];

unsigned mo5_len;
unsigned mo6_len;
unsigned to7_len;
unsigned to8_len;
unsigned to9_len;
unsigned to9p_len;

struct remap mo5_remap[30];
struct remap mo6_remap[30];
struct remap to7_remap[30];
struct remap to8_remap[30];
struct remap to9_remap[30];
struct remap to9p_remap[30];

unsigned mo5_remap_len;
unsigned mo6_remap_len;
unsigned to7_remap_len;
unsigned to8_remap_len;
unsigned to9_remap_len;
unsigned to9p_remap_len;

//-----------------------------------------------------------------------------
// Remove comments
void compact()
{
    unsigned i;
    int comm;
    comm = 0;

//    printf ("MAPLEN = %d\n",maplen);
    // Remove comments
    for (i=0;i<maplen;i++) {
        if ((map[i]=='/') && (map[i+1]=='*') && (comm==0)) {
            comm  = 1;
        }
        if ((i>0) && (map[i]=='*') && (map[i+1]=='/') && (comm==1)) {
            comm = 0;
            map[i+1]=' ';
            map[i]=' ';
        }
        if (comm) {
            map[i]=' ';
        }
    }

//    printf ("MAPLEN = %d\n",maplen);

    // Remove comments
    for (i=0;i<maplen;i++) {
        if ((map[i]=='/') && (map[i+1]=='/') && (comm==0)) {
            comm  = 1;
        }
        if ((map[i]==0xA) && (comm==1)) {
            comm = 0;
            map[i]=' ';
        }
        if (comm) {
            map[i]=' ';
        }
    }

//    printf ("MAPLEN = %d\n",maplen);

    for (i=0;i<maplen;i++) {
        if (map[i]==8)   map[i] =' ';
        if (map[i]==0xA) map[i] = ' ';
        if (map[i]==0xD) map[i] = ' ';
    }

    // Pack spaces
    
    for (i=0;i<maplen;i++) {
        while ((i+1<maplen) && (map[i]==' ') && (map[i+1]==' ')) {
           memmove(&map[i],&map[i+1],maplen-i-1);
           map[i]=' ';
           maplen--;
        }
    }
    
    for (i=0;i<maplen-2;i++) {
        while ((map[i]==')') && (map[i+1]==' ')) {
            memmove(&map[i+1],&map[i+2],maplen-i-2);
            maplen--;
        }
        while ((map[i]=='(') && (map[i+1]==' ')) {
            memmove(&map[i+1],&map[i+2],maplen-i-2);
            maplen--;
        }
        while ((map[i]==' ') && (map[i+1]==')')) {
            memmove(&map[i],&map[i+1],maplen-i-1);
            maplen--;
        }
        while ((map[i]==' ') && (map[i+1]=='(')) {
            memmove(&map[i],&map[i+1],maplen-i-1);
            maplen--;
        }
    }
    
//    printf ("MAPLEN = %d\n",maplen);

    if (map[maplen-1]==' ') maplen--;
}

//-----------------------------------------------------------------------------
// Recursive parser
void parse(int n, int *pos)
{
    int spos;
    char *str;
    int sub;
    if (map[*pos]=='(') {
        sub = 1;
       list[n].cars  = NULL;
       list[n].car = lastn;
       lastn++;
       (*pos)++;
       parse(lastn-1,pos);
    } else {
       sub = 0;
       spos = *pos;
       while ((map[*pos]!=' ')&&(map[*pos]!=')')&&(map[*pos]!='(')&&(*pos < maplen)) {
           (*pos)++;
       }
       str = (char *)malloc(*pos-spos+1);
       memcpy(str,&map[spos],*pos-spos);
       str[*pos-spos]=0;
       list[n].cars  = str;
       list[n].car = NIL;
    }
    list[n].cdr  = NIL;

    if (*pos >= maplen) return;
    if (map[*pos]==')') {
        (*pos)++;
    } else
    if ((map[*pos]==' ')||sub) {
        if (!sub) (*pos)++;
        list[n].cdr = lastn;
        lastn++;
        parse(lastn-1,pos);
    } else
    if (map[*pos]=='(') {
        list[n].cdr = lastn;
        lastn++;
        parse(lastn-1,pos);
    }
}

//-----------------------------------------------------------------------------
int find_tv = 0;
int find_n  = 0;
void find_rec(int n,char *match)
{
    //printf("%d :%s ",n,cars(n));
    if (!car(n)) {
        if (strcmp(cars(n),match) ==0) {
            find_n = n;
            find_tv = 1;
        }
    } else {
        find_rec(car(n),match);
    }
    if (cdr(n)) find_rec(cdr(n),match);
    return;
}

int find(int start,char *match)
{
    find_tv=0;
    find_n =0;
    find_rec(start,match);
    //printf ("\n");
    return find_n;
}

//-----------------------------------------------------------------------------
void print(int recurse,int pos)
{
    if (list[pos].cars) {
        printf(" %s ",list[pos].cars);
    } else {
        printf("(");
        print(recurse+1,list[pos].car);
    }
    if (list[pos].cdr) { 
        print(recurse,list[pos].cdr);
    } else {
        if (recurse<2) printf(")\n\n");
        else printf(")");
    }
}

//-----------------------------------------------------------------------------
// Parse keycodes

void parse_ps2()
{
    
    int p = cdr(find(1,"ps2"));
    int i = 1;

    memset(keys,0,512);
    
    do {
        int line = car(p);

        char *keycode = cars(line);
        int keyval;

        if (*keycode=='x') {
            keyval = strtol(&keycode[1],0,16) + 256;
        } else {
            keyval = strtol(&keycode[0],0,16);
        }
        int cdrline = cdr(line);

        keys[keyval]=i;

        char *ps2_key = cars(cdrline);
        maps[i].ps2   = ps2_key;
        
        printf("%4d > %4X : KEY=%s\n",i,keyval,ps2_key);

        p = cdr(p);
        i++;
    } while(p);

    printf ("TOTAL =%d\n",i);

}

//-----------------------------------------------------------------------------

void parse_moto(char *model,struct tomokey *mo,struct remap *re, unsigned *plen,unsigned *prelen)
{
    int p = cdr(find(1,model));
    int i = 0;
    int pre;
    char *keycode;
    char *key;
    char *key_shift;

    printf ("-----------------------------------------------------------------------------\n");
    printf ("[%s]\n",model);
    printf (" : %s\n",cars(car(p))); // "remap"
    
    pre = cdr(car(p));
    i=0;
    do {
        re[i].ps2  = cars(car(pre));
        re[i].tomo = cars(cdr(car(pre)));
        re[i].tag  = 0;
        printf ("%d : %s %s\n",pre,re[i].ps2,re[i].tomo);
        pre = cdr(pre);
        i++;
    } while (pre);
    *prelen = i;
    
    printf (" : %s\n",cars(car((cdr(p))))); // "keycodes"

    pre = cdr(car((cdr(p))));
    i=0;
    do {
        mo[i].pos       = strtol(cars(car(pre)),0,16);
        mo[i].key       = cars(cdr(car(pre)));
        mo[i].tag       = 0;
        
        printf ("%d : %2X %s\n",pre,mo[i].pos,mo[i].key);

        pre = cdr(pre);
        i++;
    } while (pre);
    *plen = i;

}

//-----------------------------------------------------------------------------

void parse_to9(char *model,struct tomokey9 *mo,struct remap *re, unsigned *plen,unsigned *prelen)
{
    int p = cdr(find(1,model));
    int i = 0;
    int pre;
    char *keycode;
    char *key;
    char *key_shift;

    printf ("-----------------------------------------------------------------------------\n");
    printf ("[%s]\n",model);
    printf (" : %s\n",cars(car(p))); // "remap"
    
    pre = cdr(car(p));
    i=0;
    do {
        re[i].ps2  = cars(car(pre));
        re[i].tomo = cars(cdr(car(pre)));
        re[i].tag  = 0;
        printf ("%d : %s %s\n",pre,re[i].ps2,re[i].tomo);
        pre = cdr(pre);
        i++;
    } while (pre);
    *prelen = i;

    printf (" : %s\n",cars(car((cdr(p))))); // "keycodes"
    pre = cdr(car((cdr(p))));
    
    /*
    keycode <>
            PRE=
            ((90 95) F1)    <>
                            ((91 96) F2)    <>
    */

    i=0;
    do {
        //printf(">>>>>>>>>>>>>>>>>\n");
        //print(0,car(pre));
        //printf("<<<<<<<<<<<<<<<<<\n");
        int base=car(pre);
        mo[i].key = cars(cdr(base));
        
        int li = car(base);
        
        
        int len = 1;
        printf (":");
        do {
            printf ("%s ",cars(li));
            if (!cdr(li)) break;
            li=cdr(li);
            len++;
        } while (1);
        printf ("\n");

        li = car(base);

        switch(len) {
            case 1:
                mo[i].pos    = strtol(cars(li),0,16);
                mo[i].pos_s  = mo[i].pos;
                mo[i].pos_c  = mo[i].pos;
                mo[i].pos_sc = mo[i].pos;
                break;
            case 2:
                mo[i].pos    = strtol(cars(li),0,16);
                mo[i].pos_s  = strtol(cars(cdr(li)),0,16);
                mo[i].pos_c  = mo[i].pos;
                mo[i].pos_sc = mo[i].pos_s;
                break;
            case 3:
                mo[i].pos    = strtol(cars(li),0,16);
                mo[i].pos_s  = strtol(cars(cdr(li)),0,16);
                mo[i].pos_c  = strtol(cars(cdr(cdr(li))),0,16);
                mo[i].pos_sc = strtol(cars(cdr(li)),0,16);
                break;
        }
        mo[i].tag       = 0;
        
        printf ("%d : %s %d : %2X %2X %2X %2X\n",pre,mo[i].key,len,
                mo[i].pos,mo[i].pos_s,mo[i].pos_c,mo[i].pos_sc);
        
        pre = cdr(pre);
        i++;
    } while (pre);
    *plen = i;

}

// CAR = pointer / FINAL string CDR = DATA

//-----------------------------------------------------------------------------
// Generate file
char header[] =
    "--------------------------------------------------------------------------------\n"
    "-- Thomson MO / TO\n"
    "--------------------------------------------------------------------------------\n"
    "-- DO 6/2025\n"
    "--------------------------------------------------------------------------------\n"
    "\n"
    "-- Keycodes\n"
    "\n"
    "--------------------------------------------------------------------------------\n"
    "\n"
    "LIBRARY IEEE;\n"
    "USE IEEE.std_logic_1164.all;\n"
    "USE IEEE.numeric_std.all;\n"
    "\n"
    "LIBRARY work;\n"
    "USE work.base_pack.ALL;\n"
    "\n"
    "-------------------------------------------------------------------------------\n"
    "\n"
    "PACKAGE kbd_pack IS\n"
    "\n";

char trailer[] =
    "\n"
    "END PACKAGE kbd_pack;\n";

//-----------------------------------------------------------------------------

void gen_kk(FILE *fo,
            char *name,
            struct tomokey  mo[],
            struct remap    mo_remap[],
            unsigned *mo_len,
            unsigned *mo_remap_len,
            unsigned caps)
{
    int i,j;
    int trv;
    char keyname[40];
    uint8_t v;

    fputs("  CONSTANT map_",fo); fputs(name,fo); 
    if (!caps) fputs("  : arr_uv8(0 TO 127) := (\n",fo);
          else fputs("  : std_logic_vector(0 TO 127) := \"",fo);

    for (i=0;i<128;i++) {
        
        if (!caps) if ((i&15)==0) fputs("    ",fo);
        
        if (maps[i].ps2==0) {
            // Invalid PS2 code
            if (!caps) fputs ("x\"FF\"",fo);
                  else fputs ("0",fo);
        } else {
            //printf ("{%s}\n",maps[i].ps2);
            if (maps[i].ps2) strcpy(keyname,maps[i].ps2);
             else strcpy(keyname,"<INVALID>");

            // Recherche dans remap => change nom si nécessaire
            for (j=0;j<*mo_remap_len;j++) {
                //printf ("<%s> [%s]\n",mo_remap[j].ps2,mo_remap[j].tomo);
                if (!strcmp(keyname,mo_remap[j].ps2)) {
                    strcpy(keyname,mo_remap[j].tomo);
                    mo_remap[j].tag  = 1;
                    //printf ("REMAP : %s %s\n",mo_remap[j].ps2,mo_remap[j].tomo);
                    break;
                }
            }

            // Recherche touche
            trv= 0;
            for (j=0;j<*mo_len;j++) {
                //printf ("%4d : :%s:\n",j,mo[j].key);
                if (!strcmp(keyname,mo[j].key)) {
                    if (trv) {
                        printf ("ERROR : Duplicate name %s\n",keyname);
                    }
                    v = mo[j].pos;
                    trv = 1;
                    mo[j].tag = 1;
                }
            }
            if (!trv) v=0xFF;
            if (!caps) fprintf(fo,"x\"%02X\"",(unsigned)v);
                else {
                    if ((keyname[0] >='A') && (keyname[0] <='Z') && (keyname[1]==0)) fprintf (fo,"1");
                                                                               else  fprintf (fo,"0");
                }
        }

        
        if (!caps) if (i<127) fputs(", ",fo);

        if (!caps) if ((i&15)==15) fputc('\n',fo);
    }
    if (!caps) fprintf(fo,"  );\n");
          else fprintf(fo,"\";\n");

    for (j=0;j<*mo_len;j++) {
        if (mo[j].tag == 0) printf ("%s : MISSING KEY : %s\n",name,mo[j].key);
    }
    for (j=0;j<*mo_remap_len;j++) {
        if (mo_remap[j].tag == 0) printf ("%s : NO MATCH : %s > %s\n",name,mo_remap[j].ps2,mo_remap[j].tomo);
    }

}

//-----------------------------------------------------------------------------
void gen_kk9(FILE *fo,
            char *name,
            struct tomokey9 mo[],
            struct remap    mo_remap[],
            unsigned *mo_len,
            unsigned *mo_remap_len)
{
    int i,j;
    int trv;
    char keyname[40];
    uint8_t v, v_s, v_c, v_sc;

    fputs("  CONSTANT map_",fo); fputs(name,fo); fputs("  : arr_uv8(0 TO 511) := (\n",fo);

    for (i=0;i<128;i++) {
        
        if ((i&7)==0) fputs("    ",fo);
        
        if (maps[i].ps2==0) {
            // Invalid PS2 code
            fputs ("x\"FF\",",fo);
            fputs ("x\"FF\",",fo);
            fputs ("x\"FF\",",fo);
            fputs ("x\"FF\"",fo);
        } else {
            //printf ("{%s}\n",maps[i].ps2);
            if (maps[i].ps2) strcpy(keyname,maps[i].ps2);
             else strcpy(keyname,"<INVALID>");

            // Recherche dans remap => change nom si nécessaire
            for (j=0;j<*mo_remap_len;j++) {
                //printf ("<%s> [%s]\n",mo_remap[j].ps2,mo_remap[j].tomo);
                if (!strcmp(keyname,mo_remap[j].ps2)) {
                    strcpy(keyname,mo_remap[j].tomo);
                    mo_remap[j].tag  = 1;
                    //printf ("REMAP : %s %s\n",mo_remap[j].ps2,mo_remap[j].tomo);
                    break;
                }
            }

            // Recherche touche
            trv= 0;
            for (j=0;j<*mo_len;j++) {
                //printf ("%4d : :%s:\n",j,mo[j].key);
                if (!strcmp(keyname,mo[j].key)) {
                    if (trv) {
                        printf ("ERROR : Duplicate name %s\n",keyname);
                    }
                    v    = mo[j].pos;
                    v_s  = mo[j].pos_s;
                    v_c  = mo[j].pos_c;
                    v_sc = mo[j].pos_sc;
                    trv = 1;
                    mo[j].tag = 1;
                }
            }
            if (!trv) { v=0xFF; v_s=0xFF; v_c=0xFF; v_sc=0xFF; }
            fprintf(fo,"x\"%02X\",",(unsigned)v);
            fprintf(fo,"x\"%02X\",",(unsigned)v_s);
            fprintf(fo,"x\"%02X\",",(unsigned)v_c);
            fprintf(fo,"x\"%02X\"" ,(unsigned)v_sc);
        }
        
        if (i<127) fputs(",",fo);
        if ((i&7)==7) fputc('\n',fo);
    }
    fprintf(fo,"  );\n");

    for (j=0;j<*mo_len;j++) {
        if (mo[j].tag == 0) printf ("%s : MISSING KEY : %s\n",name,mo[j].key);
    }
    for (j=0;j<*mo_remap_len;j++) {
        if (mo_remap[j].tag == 0) printf ("%s : NO MATCH : %s > %s\n",name,mo_remap[j].ps2,mo_remap[j].tomo);
    }
}

//-----------------------------------------------------------------------------

void gen_vhd()
{
    FILE *fo;
    int i,j;

    fo = fopen("kbd_pack.vhd","w");

    // Header
    fwrite(header,sizeof(header)-1,1,fo);

    // PS2 to compressed keycodes
    fprintf(fo,"  CONSTANT map_ps2k : arr_uv8(0 TO 511) := (\n");
    for (i=0;i<512;i++) {
        if ((i&15)==0) fputs("    ",fo);
        fprintf(fo,"x\"%02X\"",keys[i]);
        if (i<511) fputs(", ",fo);
        if ((i&15)==15) fputc('\n',fo);
    }
    fprintf(fo,"  );\n");

    // MO5 keycodes
    fputs("\n\n  -- Keymaps\n",fo);
    
    gen_kk(fo,"mo5",mo5,mo5_remap,&mo5_len,&mo5_remap_len,0);
    fputs("\n",fo);
    gen_kk(fo,"mo6",mo6,mo6_remap,&mo6_len,&mo6_remap_len,0);
    fputs("\n",fo);
    gen_kk(fo,"to7",to7,to7_remap,&to7_len,&to7_remap_len,0);
    fputs("\n",fo);
    gen_kk(fo,"to8",to8,to8_remap,&to8_len,&to8_remap_len,0);
    fputs("\n",fo);
    gen_kk(fo,"to8_caps",to8,to8_remap,&to8_len,&to8_remap_len,1);
    fputs("\n",fo);
    gen_kk9(fo,"to9p",to9p,to9p_remap,&to9p_len,&to9p_remap_len);
    fputs("\n",fo);

    // Trailer
    fwrite(trailer,sizeof(trailer)-1,1,fo);

    fclose(fo);

}
//-----------------------------------------------------------------------------
int main(int argc,char *argv[])
{
    FILE *fi;
    FILE *fo;
    unsigned i;
    int pos;

    fi = fopen("map","r");

    maplen = 0;
    do {
        fread(&map[maplen],1,1,fi);
        maplen++;
    } while (!feof(fi));
    maplen--;

    compact();

    fo = fopen("mmm","w");
    for (i=0;i<maplen;i++) {
        fwrite(&map[i],1,1,fo);
    }
    fclose(fo);
    pos = 0;
    lastn=2;
    parse(1,&pos);

    printf("----------------------------------------------------------------------\n");
    //print(0,1);
    printf ("LASTN=%d\n",lastn);

    printf ("PS2 = %d\n",find(1,"ps2"));
    printf ("MO5 = %d\n",find(1,"mo5"));
    printf ("MO6 = %d\n",find(1,"mo6"));

    parse_ps2();
    
    parse_moto("mo5", mo5, mo5_remap, &mo5_len, &mo5_remap_len);
    parse_moto("mo6", mo6, mo6_remap, &mo6_len, &mo6_remap_len);

    parse_moto("to7", to7, to7_remap, &to7_len, &to7_remap_len);
    parse_moto("to8", to8, to8_remap, &to8_len, &to8_remap_len);
    parse_to9 ("to9p",to9p,to9p_remap,&to9p_len,&to9p_remap_len);

    printf ("=============================================================================\n");
    printf ("%d %d\n",mo5_len,mo5_remap_len);
    printf ("=============================================================================\n");
    gen_vhd();
    printf ("=============================================================================\n");
    //print(0,1);

    return 0;
}
