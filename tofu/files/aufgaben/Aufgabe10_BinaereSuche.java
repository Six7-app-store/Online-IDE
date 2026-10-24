/**
 * Aufgabe 10: Binäre Suche
 *
 * Schreibe eine Methode binarySearch(int[] sortedArray, int target),
 * die den Index des gesuchten Wertes zurückgibt. Ist der Wert nicht
 * enthalten, soll -1 zurückgegeben werden.
 * Das Array ist aufsteigend sortiert.
 *
 * Beispiele:
 *   binarySearch(new int[]{1, 3, 5, 7, 9}, 5)   → 2
 *   binarySearch(new int[]{1, 3, 5, 7, 9}, 1)   → 0
 *   binarySearch(new int[]{1, 3, 5, 7, 9}, 4)   → -1
 */
public class Aufgabe10_BinaereSuche {

    public static int binarySearch(int[] sortedArray, int target) {
        // TODO: Implementierung
        return -1;
    }

    public static void main(String[] args) {
        System.out.println(binarySearch(new int[]{1, 3, 5, 7, 9}, 5));  // 2
        System.out.println(binarySearch(new int[]{1, 3, 5, 7, 9}, 1));  // 0
        System.out.println(binarySearch(new int[]{1, 3, 5, 7, 9}, 4));  // -1
    }
}
