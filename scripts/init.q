//=============================================================
// .quiz.init
//
// Initialise q-Quiz
//=============================================================
.quiz.init:{
    -1 "";
    -1 "======================================";
    -1 " Initialising q-Quiz";
    -1 "======================================";
    .quiz.current:`$();
    .quiz.history:([]
        question:`symbol$();
        input:`symbol$();
        correct:`symbol$();
        result:`boolean$();
        user:`symbol$()
    );
    / Whoever is signed in on the Flask session at the moment a result is
    / recorded - null symbol when nobody's signed in. Set by
    / .web.setCurrentUser (web/q/web_api.q), which web/qclient.py calls
    / before every request so this stays in sync with the session even
    / across q restarts. Defined here (not in web_api.q) so it always
    / exists, since console-only checker.q insert calls reference it too
    / and web_api.q only loads lazily on Flask's first request.
    .web.currentUser:`;
    .web.setCurrentUser:{[u] .web.currentUser:$[0=count u; `; `$u] };
    .quiz.loadBanks[];
    .quiz.loadBanksSyntax[];
    .quiz.loadBanksDebug[];
    .quiz.shuffleBank each key .quiz.bank;
    -1 "";
    system "l ./scripts/quiz.q";
    system "l ./hackerRank/scripts/init.q";
    system "l ./qIdioms/scripts/init.q";
    system "l ./diChallenges/scripts/init.q";
    system "l ./leetcode/scripts/init.q";
    system "l ./quantRank/scripts/init.q";
    system "l ./jobs/jobs.q";
    system "l ./fundamentals/scripts/init.q";
    system "l ./euler/scripts/init.q";
    system "l ./adventOfCode/scripts/init.q";
    initHackerRank[];
    initQIdioms[];
    initDiChallenges[];
    initLeetcode[];
    initQuantRank[];
    initFundamentals[];
    initEuler[];
    initAdventOfCode[];
    .quiz.loadResults[];
    -1 "Loaded.";
 };


.quiz.loadBanks:{
    listOfDirs:key hsym `$"./banks/";
    {system"l ./banks/",(string x),"/easy.q"}each listOfDirs;
    {system"l ./banks/",(string x),"/medium.q"}each listOfDirs;
    {system"l ./banks/",(string x),"/hard.q"}each listOfDirs;
    banks:key hsym `$"./banks/";
    .quiz.bankEasy: raze value each {` sv `.quiz,x,y}[;`easy]each banks;
    .quiz.bankMedium: raze value each {` sv `.quiz,x,y}[;`medium]each banks;
    .quiz.bankHard: raze value each {` sv `.quiz,x,y}[;`hard]each banks;
    .quiz.bank:.quiz.bankEasy,.quiz.bankMedium,.quiz.bankHard;
 };


.quiz.loadBanksSyntax:{
    listOfDirs:key hsym `$"./banksSyntax/";
    {system"l ./banksSyntax/",(string x),"/easy.q"}each listOfDirs;
    {system"l ./banksSyntax/",(string x),"/medium.q"}each listOfDirs;
    {system"l ./banksSyntax/",(string x),"/hard.q"}each listOfDirs;
    banks:key hsym `$"./banksSyntax/";
    .quiz.bankSyntaxEasy: raze value each {` sv `.quiz,x,y}[;`easy]each banks;
    .quiz.bankSyntaxMedium: raze value each {` sv `.quiz,x,y}[;`medium]each banks;
    .quiz.bankSyntaxHard: raze value each {` sv `.quiz,x,y}[;`hard]each banks;
    .quiz.bankSyntax:.quiz.bankSyntaxEasy,.quiz.bankSyntaxMedium,.quiz.bankSyntaxHard;
 };


.quiz.loadBanksDebug:{
    listOfDirs:key hsym `$"./banksDebug/";
    {system"l ./banksDebug/",(string x),"/easy.q"}each listOfDirs;
    {system"l ./banksDebug/",(string x),"/medium.q"}each listOfDirs;
    {system"l ./banksDebug/",(string x),"/hard.q"}each listOfDirs;
    banks:key hsym `$"./banksDebug/";
    .quiz.bankDebugEasy: raze value each {` sv `.quiz,x,y}[;`easy]each banks;
    .quiz.bankDebugMedium: raze value each {` sv `.quiz,x,y}[;`medium]each banks;
    .quiz.bankDebugHard: raze value each {` sv `.quiz,x,y}[;`hard]each banks;
    .quiz.bankDebug:.quiz.bankDebugEasy,.quiz.bankDebugMedium,.quiz.bankDebugHard;
 };


.quiz.shuffleQuestion:{[question]
    letters:`a`b`c`d;
    answers:value question`answers;
    correct:question`correct;
    idx:first where letters=correct;
    perm:-4?4;
    shuffled:answers perm;
    newIdx:first where perm=idx;
    `question`answers`correct!(
        question`question;
        letters!shuffled;
        letters newIdx
    )
 };


.quiz.shuffleBank:{[question]
    @[`.quiz.bank; question; :; .quiz.shuffleQuestion[.quiz.bank question]];
 };

.quiz.loadResults:{[]
    filePath:`:./results/tab;
    / `load` inside a function can create a local `tab` symbol; keep the
    / saved value in a local variable and treat a missing / empty file as an
    / empty table instead of comparing a whole table to null.
    saved:@[get;filePath;([])];
    if[0 = count saved; :()];
    upgraded:$[`user in cols saved; saved; update user:(count saved)#` from saved];
    .quiz.history:upgraded;
 };

.quiz.save:{{}
    tab::.quiz.history;
    save `:./results/tab;
 };

.quiz.init[]