import { LightningElement } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';

export default class RefreshRecordPage extends LightningElement {
    disconnectedCallback(){
    this.dispatchEvent(new RefreshEvent());
    }
}