/**
 * Aufgabe 3: Summe eines Arrays
 *
 * Schreibe eine Methode sum(int[] zahlen), die die Summe
 * aller Elemente des Arrays zurückgibt.
 *
 * Beispiele:
 *   sum(new int[]{1, 2, 3, 4, 5})  → 15
 *   sum(new int[]{})                → 0
 *   sum(new int[]{-3, 3})           → 0
 */
public class Aufgabe03_ArraySumme {

    public static int sum(int[] zahlen) {
        // TODO: Implementierung
        return 0;
    }

    public static void main(String[] args) {
        System.out.println(sum(new int[]{1, 2, 3, 4, 5}));  // 15
        System.out.println(sum(new int[]{}));                 // 0
        System.out.println(sum(new int[]{-3, 3}));            // 0
    }
}
