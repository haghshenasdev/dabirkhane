class Record {
int? shomareRadif;
String goshashte;
String date;
String sahebName;
String guy;
String fromPywa;
String shNameReside;
String tNameReside;
String onvan;
String comment;
String shomareBadi;
String wordmost2;
String tNameErsali;
String adresName;


Record({
this.shomareRadif,
required this.goshashte,
required this.date,
required this.sahebName,
required this.guy,
required this.fromPywa,
required this.shNameReside,
required this.tNameReside,
required this.onvan,
required this.comment,
required this.shomareBadi,
required this.wordmost2,
required this.tNameErsali,
required this.adresName,
});


Map<String, dynamic> toMap() => {
'Shomare_Radif': shomareRadif,
'goshashte': goshashte,
'date': date,
'saheb_name': sahebName,
'guy': guy,
'from_pywa': fromPywa,
'sh_name_reside': shNameReside,
't_name_reside': tNameReside,
'onvan': onvan,
'comment': comment,
'shomare_badi': shomareBadi,
'wordmost2': wordmost2,
't_name_ersali': tNameErsali,
'adres_name': adresName,
};
}