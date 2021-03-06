--------------------------- MODULE Peterson  ----------------------------
(***********************************************************************)
(* This is Peterson's standard two-process mutual exclusion algorithm. *)
(* A TLA+ specification is derived from a PlusCal algorithm, then      *)
(* mutual exclusion is shown using either the SMT backend or just the  *)
(* Zenon and Isabelle backends.                                        *)
(* This example is described in more detail in:                        *)
(* D. Cousineau et al.: TLA+ Proofs. 18th Intl. Symp. Formal Methods   *)
(* (FM 2012). Springer LNCS 7436, pp. 147-154, Paris 2012.             *)
(* Available online at http://www.loria.fr/~merz/papers/fm2012.html    *)
(***********************************************************************)
EXTENDS TLAPS

Not(i) == IF i = 0 THEN 1 ELSE 0

(*******
--algorithm Peterson {
   variables flag = [i \in {0, 1} |-> FALSE], turn = 0;
   fair process (proc \in {0,1}) {
     a0: while (TRUE) {
     a1:   flag[self] := TRUE;
     a2:   turn := Not(self);
     a3a:  if (flag[Not(self)]) {goto a3b} else {goto cs} ;
     a3b:  if (turn = Not(self)) {goto a3a} else {goto cs} ;
     cs:   skip;  \* critical section
     a4:   flag[self] := FALSE;
     } \* end while
    } \* end process
  }
********)

\* BEGIN TRANSLATION
VARIABLES flag, turn, pc

vars == << flag, turn, pc >>

ProcSet == ({0,1})

Init == (* Global variables *)
        /\ flag = [i \in {0, 1} |-> FALSE]
        /\ turn = 0
        /\ pc = [self \in ProcSet |-> "a0"]

a0(self) == /\ pc[self] = "a0"
            /\ pc' = [pc EXCEPT ![self] = "a1"]
            /\ UNCHANGED << flag, turn >>

a1(self) == /\ pc[self] = "a1"
            /\ flag' = [flag EXCEPT ![self] = TRUE]
            /\ pc' = [pc EXCEPT ![self] = "a2"]
            /\ turn' = turn

a2(self) == /\ pc[self] = "a2"
            /\ turn' = Not(self)
            /\ pc' = [pc EXCEPT ![self] = "a3a"]
            /\ flag' = flag

a3a(self) == /\ pc[self] = "a3a"
             /\ IF flag[Not(self)]
                   THEN /\ pc' = [pc EXCEPT ![self] = "a3b"]
                   ELSE /\ pc' = [pc EXCEPT ![self] = "cs"]
             /\ UNCHANGED << flag, turn >>

a3b(self) == /\ pc[self] = "a3b"
             /\ IF turn = Not(self)
                   THEN /\ pc' = [pc EXCEPT ![self] = "a3a"]
                   ELSE /\ pc' = [pc EXCEPT ![self] = "cs"]
             /\ UNCHANGED << flag, turn >>

cs(self) == /\ pc[self] = "cs"
            /\ TRUE
            /\ pc' = [pc EXCEPT ![self] = "a4"]
            /\ UNCHANGED << flag, turn >>

a4(self) == /\ pc[self] = "a4"
            /\ flag' = [flag EXCEPT ![self] = FALSE]
            /\ pc' = [pc EXCEPT ![self] = "a0"]
            /\ turn' = turn

proc(self) == a0(self) \/ a1(self) \/ a2(self) \/ a3a(self) \/ a3b(self)
                 \/ cs(self) \/ a4(self)

Next == (\E self \in {0,1}: proc(self))

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in {0,1} : WF_vars(proc(self))

\* END TRANSLATION

\* The following predicate defines mutual exclusion of Peterson's algorithm.
MutualExclusion == ~(pc[0] = "cs"  /\ pc[1] = "cs")

NeverCS == pc[0] # "cs"

Wait(i) == (pc[0] = "a3a") \/ (pc[0] = "a3b")
CS(i) == pc[i] = "cs"
Fairness == WF_vars(proc(0)) /\ WF_vars(proc(1))
FairSpec == Spec /\ Fairness
Liveness1 == []<>CS(0)
Liveness == (Wait(0) ~> CS(0)) /\ (Wait(1) ~> CS(1))

-----------------------------------------------------------------------------

\* The proof

TypeOK == /\ pc \in [{0,1} -> {"a0", "a1", "a2", "a3a", "a3b", "cs", "a4"}]
          /\ turn \in {0, 1}
          /\ flag \in [{0,1} -> BOOLEAN]

I == \A i \in {0, 1} :
       /\ (pc[i] \in {"a2", "a3a", "a3b", "cs", "a4"} => flag[i])
       /\ (pc[i] \in {"cs", "a4"})
            => /\ pc[Not(i)] \notin {"cs", "a4"}
               /\ (pc[Not(i)] \in {"a3a", "a3b"}) => (turn = i)

Inv == TypeOK /\ I

\* Use this specification to check with TLC that Inv is an inductive invariant.
ISpec == Inv /\ [][Next]_vars

USE DEF ProcSet

\* First proof, using SMT for showing that Inv is inductive
THEOREM Spec => []MutualExclusion
<1>1. Init => Inv
  BY DEF Init, Inv, TypeOK, I
<1>2. Inv /\ [Next]_vars => Inv'
  BY SMT DEFS Inv, TypeOK, I, Next, proc, a0, a1, a2, a3a, a3b, cs, a4, Not, vars 
<1>3. Inv => MutualExclusion
  BY DEFS Inv, I, MutualExclusion, Not
<1>4. QED
  BY <1>1, <1>2, <1>3, PTL DEF Spec

THEOREM Spec => []MutualExclusion
<1>1. Init => Inv
  BY DEF Init, Inv, TypeOK, I
<1>2. Inv /\ [Next]_vars => Inv'
  <2> SUFFICES ASSUME TypeOK,
                      I,
                      [Next]_vars
               PROVE  Inv'
    BY DEF Inv
  <2>1. ASSUME NEW self \in {0,1},
               a0(self)
        PROVE  Inv'
    BY <2>1, Zenon DEFS Inv, TypeOK, I, a0, Not, vars
  <2>2. ASSUME NEW self \in {0,1},
               a1(self)
        PROVE  Inv'
    BY <2>2, Zenon DEFS Inv, TypeOK, I, proc, a1, Not, vars
  <2>3. ASSUME NEW self \in {0,1},
               a2(self)
        PROVE  Inv'
    BY <2>3, Zenon DEFS Inv, TypeOK, I, a2, Not, vars
  <2>4. ASSUME NEW self \in {0,1},
               a3a(self)
        PROVE  Inv'
    BY <2>4, ZenonT(30) DEFS Inv, TypeOK, I, a3a, Not
  <2>5. ASSUME NEW self \in {0,1},
               a3b(self)
        PROVE  Inv'
    BY <2>5, Zenon DEFS Inv, TypeOK, I, a3b, Not
  <2>6. ASSUME NEW self \in {0,1},
               cs(self)
        PROVE  Inv'
    BY <2>6, Zenon DEFS Inv, TypeOK, I, cs, Not
  <2>7. ASSUME NEW self \in {0,1},
               a4(self)
        PROVE  Inv'
    BY <2>7, Zenon DEFS Inv, TypeOK, I, a4, Not
  <2>8. CASE UNCHANGED vars
    BY <2>8, Zenon DEFS Inv, TypeOK, I, vars
  <2>9. QED
    BY <2>1, <2>2, <2>3, <2>4, <2>5, <2>6, <2>7, <2>8, Zenon DEF Next, proc
   
<1>3. Inv => MutualExclusion
  BY Zenon DEFS Inv, I, MutualExclusion, Not
<1>4. QED
  BY <1>1, <1>2, <1>3, PTL DEF Spec


\* Second proof, using just Zenon and Isabelle
THEOREM Spec => []MutualExclusion
<1>1. Init => Inv
  BY DEFS Init, Inv, TypeOK, I
<1>2. Inv /\ [Next]_vars => Inv'
  <2>1. SUFFICES ASSUME Inv, Next PROVE Inv'
    BY DEFS Inv, TypeOK, I, vars
  <2>2. TypeOK'
    BY Inv, Next, IsaM("auto") DEFS Inv, TypeOK, Next, proc, a0, a1, a2, a3a, a3b, cs, a4, Not
  <2>3. I'
    <3>1. SUFFICES ASSUME NEW j \in {0,1}
                   PROVE  I!(j)'
      BY DEF I
    <3>2. PICK i \in {0,1} : proc(i)
      BY Next DEF Next
    <3>3. CASE i=j
      BY Inv, proc(i), i=j DEFS Inv, TypeOK, I, proc, a0, a1, a2, a3a, a3b, cs, a4, Not
    <3>4. CASE i#j
      BY Inv, proc(i), i#j DEFS Inv, TypeOK, I, proc, a0, a1, a2, a3a, a3b, cs, a4, Not
    <3>5. QED
      BY <3>3, <3>4
  <2>4. QED
    BY <2>2, <2>3 DEF Inv
<1>3. Inv => MutualExclusion
  BY DEFS Inv, I, MutualExclusion, Not
<1>4. QED
  BY <1>1, <1>2, <1>3, PTL DEF Spec

-----------

 \*(flag[1] \/ turn = 1)
QCS == CS(0)
Q2 == Wait(0) /\ Wait(1)
Q3 == Wait(0) /\ CS(1)
Q4 == Wait(0) /\ pc[1]="a4"
Q5 == Wait(0) /\ pc[1] \in {"a0","a1"} /\ \neg flag[1]
Q6 == Wait(0) /\ pc[1] = "a2"
Q7 == Wait(0) /\ Wait(1) /\ turn = 0
Q8 == pc[0] = "a3b" /\ Wait(1) /\ turn = 0
Q9 == Wait(0) /\ pc[1] \in {"a0","a1"} /\ \neg flag[1] /\ pc[0] = "a3b"
Q10 == Wait(0) /\ pc[1] = "a2" /\ \neg flag[1] /\ pc[0] = "a3a"

LEMMA ASSUME NEW STATE P, []<>P PROVE <>P BY PTL 

LEMMA [][turn'=1]_turn /\ WF_turn(turn'=1) => <>(turn=1) \* original schema has (TRUE ~> turn=1), but that implies []<>turn=1 
<1>1. TRUE /\ [turn'=1]_turn => TRUE' \/ (turn'=1) OMITTED
<1>2. TRUE /\ <<turn'=1>>_turn => (turn=1)' OMITTED
<1>3. ~(turn=1) => ENABLED <<turn'=1>>_turn OMITTED
<1>.QED  BY <1>1, <1>2, <1>3, PTL

\* Liveness proof -- not provable
LEMMA WF1 ==
  ASSUME NEW STATE P, NEW STATE Q, NEW ACTION N, NEW STATE v, NEW ACTION A,
         (P /\ [N]_v => P' \/ Q'),
         (P /\ <<A>>_v => Q'),
         (P => ENABLED <<A>>_v)
  PROVE  [][N]_v /\ WF_v(A) => (P ~> Q)
BY PTL

\*A == \neg [\neg pc[1]'="cs"]_vars


LEMMA TypeOK /\ [][Next]_vars /\ WF_vars(a2(0)) /\ Q2 => (Q2 ~> (Q3 \/ QCS))
<1>1. Q2 /\ [Next]_vars => (Q2' \/ (Q3 \/ QCS)')
    \* <2>1 should need more expansion, is this a bug?
    <2>1.ASSUME Q2, [Next]_vars 
         PROVE  Q2' \/ Q3' \/ QCS' BY <2>1, LS4 DEF Q2, Wait, CS, vars
    <2> QED BY <2>1
<1>2. Q2 /\ <<a2(0)>>_vars => (Q3 \/ QCS)' OMITTED
<1>3. Q2 => ENABLED ( <<a2(0)>>_vars ) OMITTED
<1> QED BY <1>1, <1>2, <1>3, PTL

LEMMA /\ Q2 ~> (Q3 \/ QCS)
      /\ Q3 ~> Q4
      /\ Q4 ~> Q5
      /\ Q5 ~> (Q6 \/ Q7)
      /\ Q6 ~> Q8
      /\ Q7 ~> Q8
      /\ Q8 ~> Q9
      /\ Q9 ~> QCS 
      => Q2 ~> QCS
      BY LS4


THEOREM FairSpec => Liveness
<1>1. FairSpec => Wait(0) ~> CS(0)
    <2>1. FairSpec => ((Wait(0) /\ ENABLED<<proc(0)>>_vars) ~> CS(0))
        <3>1. (FairSpec /\ Q2 => [][Q2']_vars)
        <3>2. TRUE
        <3> QED BY <3>1, <3>2, PTL
    <2>2. FairSpec => Wait(0) /\ ~ENABLED<<proc(0)>>_vars ~> CS(0)
    <2> QED BY <2>1, <2>2, PTL DEF FairSpec

<1>2. FairSpec => Wait(1) ~> CS(1)
    \* similarily to <1>1
<1> QED BY <1>1, <1>2, PTL DEF Liveness

THEOREM OldAttempt == FairSpec => Liveness
<1>1. FairSpec => Wait(0) ~> CS(0)
    <2>1. FairSpec => ((Wait(0) /\ ENABLED<<proc(0)>>_vars) ~> CS(0))
        <3>1. FairSpec => ((Wait(0) /\ ENABLED<<proc(0)>>_vars /\ (pc[1] = "a1")) ~> CS(0))
        <3>2. FairSpec => ((Wait(0) /\ ENABLED<<proc(0)>>_vars /\ ~(pc[1] = "a1")) ~> CS(0))
        <3> QED BY <3>1, <3>2, PTL
    <2>2. FairSpec => Wait(0) /\ ~ENABLED<<proc(0)>>_vars ~> CS(0)
    <2> QED BY <2>1, <2>2, PTL DEF FairSpec

<1>2. FairSpec => Wait(1) ~> CS(1)
    \* similarily to <1>1
<1> QED BY <1>1, <1>2, PTL DEF Liveness

=============================================================================
